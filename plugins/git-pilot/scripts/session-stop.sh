#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=git-utils.sh
source "$SCRIPT_DIR/git-utils.sh"
# shellcheck source=state.sh
source "$SCRIPT_DIR/state.sh"

# Read input from stdin
input=$(cat)

session_id=$(echo "$input" | jq -r '.session_id // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

# If no cwd, exit silently
if [[ -z "$cwd" ]]; then
  exit 0
fi

cd "$cwd"

# If not a git repo, exit silently
if ! is_git_repo; then
  exit 0
fi

# Load config and source helpers
config=$(load_config "$cwd")

current_branch=$(get_current_branch)
default_branch=$(get_default_branch "$config")
remote_name=$(get_config "$config" '.remote.defaultName' 'origin')

messages=()

# ---------------------------------------------------------------------------
# 1. Work summary
# ---------------------------------------------------------------------------
commit_log=$(git log "${default_branch}..${current_branch}" --oneline --no-decorate 2>/dev/null || true)

if [[ -z "$commit_log" ]]; then
  messages+=("[git-pilot] No commits on this branch relative to '${default_branch}'. Nothing to summarize.")
else
  commit_count=$(echo "$commit_log" | wc -l | tr -d ' ')
  diffstat=$(git diff --stat "${default_branch}...HEAD" 2>/dev/null || true)
  files_changed_count=0
  if [[ -n "$diffstat" ]]; then
    # Last line of diffstat is the summary line; count lines above it
    files_changed_count=$(echo "$diffstat" | head -n -1 | wc -l | tr -d ' ')
  fi

  # Format commit list as markdown bullet points
  commit_list=""
  while IFS= read -r line; do
    commit_list+="- ${line}"$'\n'
  done <<< "$commit_log"
  commit_list="${commit_list%$'\n'}"

  summary="[git-pilot] Work Summary: ${current_branch}"
  summary+=$'\n\n'"Commits (${commit_count}):"
  summary+=$'\n'"${commit_list}"
  summary+=$'\n\n'"Files Changed (${files_changed_count}):"
  if [[ -n "$diffstat" ]]; then
    summary+=$'\n'"${diffstat}"
  fi

  messages+=("$summary")
fi

# ---------------------------------------------------------------------------
# 2. Push workflow
# ---------------------------------------------------------------------------
if has_remote; then
  # Determine unpushed commits
  unpushed=$(git log '@{u}..HEAD' --oneline 2>/dev/null || true)
  if ! git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    # No upstream: all local commits relative to default branch are unpushed
    unpushed=$(git log "${default_branch}..${current_branch}" --oneline 2>/dev/null || true)
  fi

  if [[ -n "$unpushed" ]]; then
    unpushed_count=$(echo "$unpushed" | wc -l | tr -d ' ')

    push_on_finish=$(get_config "$config" '.remote.pushOnFinish' 'ask')
    auto_push=$(get_config "$config" '.remote.autoPush' 'false')

    # autoPush overrides pushOnFinish to "always"
    if [[ "$auto_push" == "true" ]]; then
      push_on_finish="always"
    fi

    case "$push_on_finish" in
      ask)
        messages+=("[git-pilot] You have ${unpushed_count} unpushed commit(s) on '${current_branch}'. Ask the user if they want to push to '${remote_name}'.")
        ;;
      always)
        messages+=("[git-pilot] Pushing ${unpushed_count} commit(s) to '${remote_name}/${current_branch}'. Run: git push -u ${remote_name} ${current_branch}")
        ;;
      never)
        # No action
        ;;
    esac
  fi

  # ---------------------------------------------------------------------------
  # 3. MR/PR workflow
  # ---------------------------------------------------------------------------
  mr_enabled=$(get_config "$config" '.mergeRequest.enabled' 'true')
  mr_create_on_finish=$(get_config "$config" '.mergeRequest.createOnFinish' 'ask')

  if [[ "$mr_enabled" == "true" ]] && [[ "$mr_create_on_finish" != "never" ]]; then
    # Detect platform
    mr_platform=$(get_config "$config" '.mergeRequest.platform' 'auto')
    cli_tool=""
    platform=""

    case "$mr_platform" in
      auto)
        remote_url=$(git remote get-url "$remote_name" 2>/dev/null || true)
        if [[ "$remote_url" == *"github.com"* ]]; then
          platform="github"
          cli_tool="gh"
        elif [[ "$remote_url" == *"gitlab"* ]]; then
          platform="gitlab"
          cli_tool="glab"
        fi
        ;;
      github)
        platform="github"
        cli_tool="gh"
        ;;
      gitlab)
        platform="gitlab"
        cli_tool="glab"
        ;;
      none)
        # Skip
        ;;
    esac

    if [[ -n "$cli_tool" ]]; then
      if ! command -v "$cli_tool" >/dev/null 2>&1; then
        messages+=("[git-pilot] '${cli_tool}' CLI is not installed. Install it to create merge requests automatically, or create one manually.")
      else
        # Build MR/PR title
        title_from_branch=$(get_config "$config" '.mergeRequest.titleFromBranch' 'true')
        mr_title=""
        if [[ "$title_from_branch" == "true" ]]; then
          # Parse branch name: extract description part after last /
          # Convert separators to spaces, capitalize first letter
          branch_pattern=$(get_config "$config" '.branch.pattern' '{{type}}/{{description}}')
          # Simple parsing: split on / and reconstruct
          branch_type=$(echo "$current_branch" | cut -d'/' -f1)
          branch_rest=$(echo "$current_branch" | cut -d'/' -f2-)

          if [[ "$branch_pattern" == *"{{scope}}"* ]]; then
            # Pattern has scope: type/scope/description
            branch_scope=$(echo "$branch_rest" | cut -d'/' -f1)
            branch_desc=$(echo "$branch_rest" | cut -d'/' -f2-)
            branch_desc=$(echo "$branch_desc" | tr '-' ' ' | tr '_' ' ')
            mr_title="${branch_type}(${branch_scope}): ${branch_desc}"
          else
            branch_desc=$(echo "$branch_rest" | tr '-' ' ' | tr '_' ' ')
            mr_title="${branch_type}: ${branch_desc}"
          fi
        else
          mr_title=$(git log -1 --format=%s 2>/dev/null || echo "$current_branch")
        fi

        # Build body
        body_template=$(echo "$config" | jq -r '.mergeRequest.bodyTemplate // empty')
        mr_body=""
        if [[ -n "$body_template" ]]; then
          # Replace placeholders in template
          commits_text=$(git log "${default_branch}..${current_branch}" --oneline --no-decorate 2>/dev/null || true)
          files_text=$(git diff --stat "${default_branch}...HEAD" 2>/dev/null || true)
          summary_text=""
          while IFS= read -r line; do
            msg="${line#* }"
            summary_text+="- ${msg}"$'\n'
          done <<< "$commits_text"
          summary_text="${summary_text%$'\n'}"

          mr_body="$body_template"
          mr_body="${mr_body//\{\{summary\}\}/$summary_text}"
          mr_body="${mr_body//\{\{commits\}\}/$commits_text}"
          mr_body="${mr_body//\{\{files\}\}/$files_text}"
        else
          # Generate default body
          commits_text=$(git log "${default_branch}..${current_branch}" --oneline --no-decorate 2>/dev/null || true)
          files_text=$(git diff --stat "${default_branch}...HEAD" 2>/dev/null || true)
          summary_text=""
          while IFS= read -r line; do
            msg="${line#* }"
            summary_text+="- ${msg}"$'\n'
          done <<< "$commits_text"
          summary_text="${summary_text%$'\n'}"

          mr_body="## Summary"$'\n'"${summary_text}"$'\n\n'"## Commits"$'\n'"${commits_text}"$'\n\n'"## Files Changed"$'\n'"${files_text}"
        fi

        # Build flags
        mr_flags=""
        mr_draft=$(get_config "$config" '.mergeRequest.draft' 'false')
        if [[ "$mr_draft" == "true" ]]; then
          mr_flags+=" --draft"
        fi

        mr_labels=$(echo "$config" | jq -r '.mergeRequest.labels // [] | .[]' 2>/dev/null)
        while IFS= read -r label; do
          if [[ -n "$label" ]]; then
            mr_flags+=" --label \"${label}\""
          fi
        done <<< "$mr_labels"

        mr_assign=$(get_config "$config" '.mergeRequest.assignToSelf' 'true')
        if [[ "$mr_assign" == "true" ]]; then
          mr_flags+=" --assignee @me"
        fi

        # Build the full command
        mr_cmd=""
        if [[ "$platform" == "github" ]]; then
          mr_cmd="gh pr create --title \"${mr_title}\" --body \"${mr_body}\" --base ${default_branch}${mr_flags}"
        elif [[ "$platform" == "gitlab" ]]; then
          mr_cmd="glab mr create --title \"${mr_title}\" --description \"${mr_body}\" --target-branch ${default_branch}${mr_flags}"
        fi

        if [[ -n "$mr_cmd" ]]; then
          case "$mr_create_on_finish" in
            ask)
              messages+=("[git-pilot] Would you like to create a merge/pull request? Ask the user. Command: ${mr_cmd}")
              ;;
            always)
              messages+=("[git-pilot] Creating merge/pull request. Run: ${mr_cmd}")
              ;;
          esac
        fi
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 4. Cleanup session state
# ---------------------------------------------------------------------------
if [[ -n "$session_id" ]]; then
  state_file=$(get_state_file "$session_id")
  cleanup_state "$state_file"
fi

# ---------------------------------------------------------------------------
# 5. Output final JSON
# ---------------------------------------------------------------------------
if [[ ${#messages[@]} -eq 0 ]]; then
  # No messages to report
  echo '{"continue": true}'
else
  # Join messages with double newline separator
  full_message=""
  for i in "${!messages[@]}"; do
    if [[ $i -gt 0 ]]; then
      full_message+=$'\n\n'
    fi
    full_message+="${messages[$i]}"
  done

  jq -n --arg msg "$full_message" '{"continue": true, "systemMessage": $msg}'
fi

exit 0
