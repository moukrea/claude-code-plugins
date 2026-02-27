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
# shellcheck source=agent.sh
source "$SCRIPT_DIR/agent.sh"

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
# Agent context: attempt silent rebase, skip summary, exit early
# ---------------------------------------------------------------------------
if is_agent_context "$session_id"; then
  if [[ "$session_had_changes" == "true" ]] && has_remote; then
    auto_rebase=$(get_config "$config" '.rebase.autoRebaseBeforePush' 'true')
    if [[ "$auto_rebase" == "true" ]] && [[ -n "$current_branch" ]] && [[ "$current_branch" != "$default_branch" ]]; then
      # shellcheck source=rebase.sh
      source "$SCRIPT_DIR/rebase.sh"
      drift_status=$(get_base_branch_drift "$current_branch" "$default_branch" "$remote_name" || echo "")
      case "$drift_status" in
        drifted:*)
          rebase_result=$(attempt_rebase "${remote_name}/${default_branch}" || true)
          if [[ "$rebase_result" == "conflict" ]]; then
            git rebase --abort 2>/dev/null || true
          fi
          ;;
      esac
    fi
  fi

  # Worktree cleanup still runs for agents
  # shellcheck source=worktree.sh
  source "$SCRIPT_DIR/worktree.sh"
  registry=$(list_worktrees)
  active_count=$(echo "$registry" | jq '.worktrees | length')
  if [[ "$active_count" -gt 0 ]]; then
    cleanup_on_merge=$(get_config "$config" '.worktree.cleanupOnMerge' 'true')
    if [[ "$cleanup_on_merge" == "true" ]]; then
      echo "$registry" | jq -r '.worktrees[] | select(.status == "active") | .path' | \
      while IFS= read -r wt_path; do
        if [[ -z "$wt_path" ]]; then continue; fi
        if [[ -d "$wt_path" ]]; then
          wt_branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || true)
          if [[ -n "$wt_branch" ]] && git branch --merged "$default_branch" 2>/dev/null | grep -q "$wt_branch"; then
            remove_worktree "$wt_path" "false" || true
          fi
        else
          unregister_worktree "$wt_path"
        fi
      done
    fi
  fi

  # Cleanup session state
  if [[ -n "$session_id" ]]; then
    state_file=$(get_state_file "$session_id")
    cleanup_state "$state_file"
  fi

  echo '{"continue": true}'
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Work summary (only if changes were made during this session)
#    Suppressed for agents (handled by early exit above).
# ---------------------------------------------------------------------------
if [[ "$session_had_changes" == "true" ]]; then
  if [[ -n "$head_at_start" ]]; then
    commit_count=$(git rev-list --count "${head_at_start}..HEAD" 2>/dev/null || echo "0")
    files_changed_count=$(git diff --name-only "${head_at_start}...HEAD" 2>/dev/null | wc -l | tr -d ' ')
  else
    commit_count=$(git rev-list --count "${default_branch}..${current_branch}" 2>/dev/null || echo "0")
    files_changed_count=$(git diff --name-only "${default_branch}...HEAD" 2>/dev/null | wc -l | tr -d ' ')
  fi

  if [[ "$commit_count" -gt 0 ]]; then
    messages+=("[git-pilot] Session: ${commit_count} commit(s), ${files_changed_count} file(s) changed on '${current_branch}'")
  fi
fi

# ---------------------------------------------------------------------------
# 1.5. Base branch drift detection and rebase
#       Suppressed for agents (handled by early exit above).
# ---------------------------------------------------------------------------
if [[ "$session_had_changes" == "true" ]] && has_remote; then
  auto_rebase=$(get_config "$config" '.rebase.autoRebaseBeforePush' 'true')
  if [[ "$auto_rebase" == "true" ]] && [[ -n "$current_branch" ]] && [[ "$current_branch" != "$default_branch" ]]; then
    # shellcheck source=rebase.sh
    source "$SCRIPT_DIR/rebase.sh"
    drift_status=$(get_base_branch_drift "$current_branch" "$default_branch" "$remote_name" || echo "")
    case "$drift_status" in
      drifted:*)
        drift_count="${drift_status#drifted:}"
        messages+=("[git-pilot] '${default_branch}' has ${drift_count} new commit(s) -- consider rebasing before push")
        rebase_result=$(attempt_rebase "${remote_name}/${default_branch}" || true)
        case "$rebase_result" in
          success)
            messages+=("[git-pilot] Auto-rebase onto '${default_branch}' succeeded")
            ;;
          conflict)
            git rebase --abort 2>/dev/null || true
            messages+=("[git-pilot] Auto-rebase aborted (conflicts) -- manual rebase needed")
            ;;
        esac
        ;;
    esac
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
        messages+=("[git-pilot] Auto-push: run 'git push -u ${remote_name} ${current_branch}'")
        ;;
      *)
        # Only show unpushed count when auto-push is not emitted (auto-push implies unpushed)
        messages+=("[git-pilot] ${unpushed_count} unpushed commit(s) remaining")
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
      if [[ "$platform" == "github" ]]; then
        messages+=("[git-pilot] Auto-MR: run 'gh pr create --base ${default_branch}'")
      elif [[ "$platform" == "gitlab" ]]; then
        messages+=("[git-pilot] Auto-MR: run 'glab mr create --target-branch ${default_branch}'")
      fi
    fi
    # If CLI tool is missing, stay silent — user can use /finish or create MR manually
  fi
fi

# ---------------------------------------------------------------------------
# 3.5. Worktree cleanup — remove merged worktrees, unregister stale entries
# ---------------------------------------------------------------------------
# shellcheck source=worktree.sh
source "$SCRIPT_DIR/worktree.sh"
registry=$(list_worktrees)
active_count=$(echo "$registry" | jq '.worktrees | length')
if [[ "$active_count" -gt 0 ]]; then
  cleanup_on_merge=$(get_config "$config" '.worktree.cleanupOnMerge' 'true')
  if [[ "$cleanup_on_merge" == "true" ]]; then
    echo "$registry" | jq -r '.worktrees[] | select(.status == "active") | .path' | \
    while IFS= read -r wt_path; do
      if [[ -z "$wt_path" ]]; then continue; fi
      if [[ -d "$wt_path" ]]; then
        wt_branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || true)
        if [[ -n "$wt_branch" ]] && git branch --merged "$default_branch" 2>/dev/null | grep -q "$wt_branch"; then
          remove_worktree "$wt_path" "false" || true
        fi
      else
        unregister_worktree "$wt_path"
      fi
    done
  fi
  remaining=$(list_worktrees | jq '.worktrees | length')
  if [[ "$remaining" -gt 0 ]]; then
    messages+=("[git-pilot] ${remaining} active worktree(s) remaining")
  fi
fi

# ---------------------------------------------------------------------------
# 4. Cleanup session state
# ---------------------------------------------------------------------------
if [[ -n "$session_id" ]]; then
  state_file=$(get_state_file "$session_id")
  cleanup_state "$state_file"
fi

# Cap at 5 lines per spec
messages=("${messages[@]:0:5}")

# ---------------------------------------------------------------------------
# 5. Output final JSON
# ---------------------------------------------------------------------------
if [[ ${#messages[@]} -eq 0 ]]; then
  echo '{"continue": true}'
else
  full_message=""
  for i in "${!messages[@]}"; do
    if [[ $i -gt 0 ]]; then
      full_message+=$'\n'
    fi
    full_message+="${messages[$i]}"
  done

  jq -n --arg ctx "$full_message" '{"continue": true, "additionalContext": $ctx}'
fi

exit 0
