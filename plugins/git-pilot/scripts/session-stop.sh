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

# ---------------------------------------------------------------------------
# Detect whether HEAD moved during this session
# ---------------------------------------------------------------------------
head_at_start=""
if [[ -n "$session_id" ]]; then
  state_file=$(get_state_file "$session_id")
  state=$(read_state "$state_file")
  head_at_start=$(echo "$state" | jq -r '.headAtStart // empty')
fi

current_head=$(git rev-parse HEAD 2>/dev/null || true)

# If HEAD hasn't moved since session start, there's nothing to report
session_had_changes=false
if [[ -n "$head_at_start" ]] && [[ "$head_at_start" != "$current_head" ]]; then
  session_had_changes=true
elif [[ -z "$head_at_start" ]]; then
  # No state file (e.g. session_id was empty) — fall back to showing summary
  # only if there are branch commits at all
  commit_log=$(git log "${default_branch}..${current_branch}" --oneline --no-decorate 2>/dev/null || true)
  if [[ -n "$commit_log" ]]; then
    session_had_changes=true
  fi
fi

messages=()

# ---------------------------------------------------------------------------
# 1. Work summary (only if changes were made during this session)
# ---------------------------------------------------------------------------
if [[ "$session_had_changes" == "true" ]]; then
  # Show only session commits when possible, fall back to full branch diff
  if [[ -n "$head_at_start" ]]; then
    commit_log=$(git log "${head_at_start}..HEAD" --oneline --no-decorate 2>/dev/null || true)
    diffstat=$(git diff --stat "${head_at_start}...HEAD" 2>/dev/null || true)
  else
    commit_log=$(git log "${default_branch}..${current_branch}" --oneline --no-decorate 2>/dev/null || true)
    diffstat=$(git diff --stat "${default_branch}...HEAD" 2>/dev/null || true)
  fi

  if [[ -n "$commit_log" ]]; then
    commit_count=$(echo "$commit_log" | wc -l | tr -d ' ')
    files_changed_count=0
    if [[ -n "$diffstat" ]]; then
      files_changed_count=$(echo "$diffstat" | head -n -1 | wc -l | tr -d ' ')
    fi

    commit_list=""
    while IFS= read -r line; do
      commit_list+="- ${line}"$'\n'
    done <<< "$commit_log"
    commit_list="${commit_list%$'\n'}"

    summary="[git-pilot] Session Summary: ${current_branch}"
    summary+=$'\n\n'"Commits (${commit_count}):"
    summary+=$'\n'"${commit_list}"
    summary+=$'\n\n'"Files Changed (${files_changed_count}):"
    if [[ -n "$diffstat" ]]; then
      summary+=$'\n'"${diffstat}"
    fi

    messages+=("$summary")
  fi
fi

# ---------------------------------------------------------------------------
# 2. Push workflow (only "always" mode — "ask" is handled by /finish skill)
# ---------------------------------------------------------------------------
if [[ "$session_had_changes" == "true" ]] && has_remote; then
  unpushed=$(git log '@{u}..HEAD' --oneline 2>/dev/null || true)
  if ! git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    unpushed=$(git log "${default_branch}..${current_branch}" --oneline 2>/dev/null || true)
  fi

  if [[ -n "$unpushed" ]]; then
    unpushed_count=$(echo "$unpushed" | wc -l | tr -d ' ')

    push_on_finish=$(get_config "$config" '.remote.pushOnFinish' 'ask')
    auto_push=$(get_config "$config" '.remote.autoPush' 'false')

    if [[ "$auto_push" == "true" ]]; then
      push_on_finish="always"
    fi

    case "$push_on_finish" in
      always)
        messages+=("[git-pilot] Pushing ${unpushed_count} commit(s) to '${remote_name}/${current_branch}'. Run: git push -u ${remote_name} ${current_branch}")
        ;;
      *)
        # "ask" and "never" are silent in the stop hook.
        # Use /finish skill for interactive push/MR workflows.
        ;;
    esac
  fi

  # ---------------------------------------------------------------------------
  # 3. MR/PR workflow (only "always" mode — "ask" is handled by /finish skill)
  # ---------------------------------------------------------------------------
  mr_enabled=$(get_config "$config" '.mergeRequest.enabled' 'true')
  mr_create_on_finish=$(get_config "$config" '.mergeRequest.createOnFinish' 'ask')

  if [[ "$mr_enabled" == "true" ]] && [[ "$mr_create_on_finish" == "always" ]]; then
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
        ;;
    esac

    if [[ -n "$cli_tool" ]] && command -v "$cli_tool" >/dev/null 2>&1; then
      title_from_branch=$(get_config "$config" '.mergeRequest.titleFromBranch' 'true')
      mr_title=""
      if [[ "$title_from_branch" == "true" ]]; then
        branch_pattern=$(get_config "$config" '.branch.pattern' '{{type}}/{{description}}')
        branch_type=$(echo "$current_branch" | cut -d'/' -f1)
        branch_rest=$(echo "$current_branch" | cut -d'/' -f2-)

        if [[ "$branch_pattern" == *"{{scope}}"* ]]; then
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

      body_template=$(echo "$config" | jq -r '.mergeRequest.bodyTemplate // empty')
      mr_body=""
      if [[ -n "$body_template" ]]; then
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

      mr_cmd=""
      if [[ "$platform" == "github" ]]; then
        mr_cmd="gh pr create --title \"${mr_title}\" --body \"${mr_body}\" --base ${default_branch}${mr_flags}"
      elif [[ "$platform" == "gitlab" ]]; then
        mr_cmd="glab mr create --title \"${mr_title}\" --description \"${mr_body}\" --target-branch ${default_branch}${mr_flags}"
      fi

      if [[ -n "$mr_cmd" ]]; then
        messages+=("[git-pilot] Creating merge/pull request. Run: ${mr_cmd}")
      fi
    fi
    # If CLI tool is missing, stay silent — user can use /finish or create MR manually
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
  echo '{"continue": true}'
else
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
