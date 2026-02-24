#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=./git-utils.sh
source "$SCRIPT_DIR/git-utils.sh"
# shellcheck source=./state.sh
source "$SCRIPT_DIR/state.sh"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [[ -z "$CWD" ]]; then
  CWD="."
fi

cd "$CWD"

CONFIG=$(load_config "$CWD")

messages=()

# Step 5: Check dependencies
if ! command -v git >/dev/null 2>&1; then
  messages+=("[git-pilot] Warning: git is not installed. Git workflow features are disabled.")
fi

if ! command -v jq >/dev/null 2>&1; then
  messages+=("[git-pilot] Warning: jq is not installed. Configuration loading may not work correctly.")
fi

# Step 6: Git init check
if ! is_git_repo; then
  auto_init=$(get_config "$CONFIG" '.git.autoInit' 'true')
  default_branch=$(get_config "$CONFIG" '.git.defaultBranch' 'main')

  if [[ "$auto_init" == "true" ]]; then
    if git init -b "$default_branch" >/dev/null 2>&1; then
      if [[ ! -f ".gitignore" ]]; then
        touch .gitignore
      fi
      messages+=("[git-pilot] Initialized git repository with default branch '${default_branch}'.")
    else
      messages+=("[git-pilot] Warning: Failed to initialize git repository.")
    fi
  else
    messages+=("[git-pilot] Warning: Current directory is not a git repository. Run 'git init' to initialize one.")
  fi
fi

# Step 6a: Fetch remote (after git init check, before branch detection)
if is_git_repo && has_remote; then
  auto_fetch=$(get_config "$CONFIG" '.git.autoFetch' 'true')
  remote_name=$(get_config "$CONFIG" '.remote.defaultName' 'origin')
  if [[ "$auto_fetch" == "true" ]]; then
    retries=$(get_config "$CONFIG" '.git.fetchRetries' '2')
    if ! fetch_with_retry "$remote_name" "$CONFIG"; then
      messages+=("[git-pilot] Warning: Could not fetch from '${remote_name}' after ${retries} attempts. Network may be unavailable. Proceeding without remote sync.")
    fi
  fi
fi

# Step 7: Branch detection (only if we are in a git repo now)
current_branch=""
default_branch=$(get_config "$CONFIG" '.git.defaultBranch' 'main')

if is_git_repo; then
  current_branch=$(get_current_branch)

  # Step 7a: Detached HEAD detection
  if [[ -z "$current_branch" ]]; then
    head_sha=$(git rev-parse --short HEAD 2>/dev/null || true)
    prev_branch=$(git reflog show --format='%gs' 2>/dev/null \
      | grep -m1 'checkout: moving from' \
      | sed 's/checkout: moving from \([^ ]*\) to .*/\1/' || true)
    if [[ -n "$prev_branch" ]]; then
      messages+=("[git-pilot] Detached HEAD at ${head_sha}. Previous branch was '${prev_branch}'. Prompt the user: return to '${prev_branch}', create a new branch from HEAD, or continue in detached state.")
    else
      messages+=("[git-pilot] Detached HEAD at ${head_sha}. Prompt the user: create a new branch from HEAD or continue in detached state.")
    fi
  fi

  # Step 7b: Branch freshness check
  if has_remote && [[ -n "$current_branch" ]]; then
    remote_name=$(get_config "$CONFIG" '.remote.defaultName' 'origin')
    tracking_status=$(get_branch_tracking_status "$current_branch" "$remote_name")
    case "$tracking_status" in
      behind:*)
        behind_count="${tracking_status#behind:}"
        if git merge --ff-only "${remote_name}/${current_branch}" >/dev/null 2>&1; then
          messages+=("[git-pilot] Branch '${current_branch}' was ${behind_count} commit(s) behind '${remote_name}/${current_branch}'. Fast-forwarded to latest.")
        else
          messages+=("[git-pilot] Branch '${current_branch}' is ${behind_count} commit(s) behind '${remote_name}/${current_branch}' but fast-forward failed. Prompt the user: pull with merge, reset to remote, or continue as-is.")
        fi
        ;;
      diverged:*:*)
        IFS=':' read -r _ ahead_count behind_count <<< "$tracking_status"
        messages+=("[git-pilot] Branch '${current_branch}' has diverged from '${remote_name}/${current_branch}' (${ahead_count} local, ${behind_count} remote). Prompt the user: rebase onto remote, merge remote, reset to remote, or continue.")
        ;;
      ahead:*)
        ahead_count="${tracking_status#ahead:}"
        messages+=("[git-pilot] Branch '${current_branch}' is ${ahead_count} commit(s) ahead of '${remote_name}/${current_branch}'. Unpushed changes.")
        ;;
      # up-to-date and no-remote: no message
    esac
  fi

  # Step 7c: Branch creation prompt (existing v1 logic)
  auto_create=$(get_config "$CONFIG" '.branch.autoCreate' 'true')

  if [[ "$auto_create" == "true" ]] && [[ "$current_branch" == "$default_branch" ]]; then
    branch_pattern=$(get_config "$CONFIG" '.branch.pattern' '{{type}}/{{description}}')
    branch_types=$(echo "$CONFIG" | jq -r '.branch.types // ["feat","fix","refactor","docs","test","chore","style","perf","build","ci"] | join(", ")')

    if has_uncommitted_changes; then
      messages+=("[git-pilot] On '${default_branch}' with uncommitted changes. Prompt the user: stash and create branch, commit first, or continue on '${default_branch}'.")
    else
      messages+=("[git-pilot] On default branch '${default_branch}'. Prompt the user to create a branch before making changes. Pattern: ${branch_pattern}, types: ${branch_types}.")
    fi
  fi
fi

# Step 8: Remote detection (only if we are in a git repo)
if is_git_repo; then
  if ! has_remote; then
    prompt_remote=$(get_config "$CONFIG" '.remote.promptForRemote' 'true')
    skip_remote=$(get_config "$CONFIG" '.remote.skipRemotePrompt' 'false')

    if [[ "$prompt_remote" == "true" ]] && [[ "$skip_remote" == "false" ]]; then
      messages+=("[git-pilot] No git remote configured. Prompt the user to add one or skip.")
    fi
  fi
fi

# Step 9: Initialize session state (extended 5-arg form)
if [[ -n "$SESSION_ID" ]]; then
  previous_branch="$current_branch"
  base_branch="$default_branch"
  branch_purpose=""
  if [[ -n "$current_branch" ]] && [[ "$current_branch" != "$default_branch" ]]; then
    branch_purpose=$(derive_branch_purpose "$current_branch")
    configured_base=$(git config "branch.${current_branch}.merge" 2>/dev/null | sed 's|refs/heads/||' || true)
    if [[ -n "$configured_base" ]]; then
      base_branch="$configured_base"
    fi
  fi
  init_state "$SESSION_ID" "$current_branch" "$previous_branch" "$base_branch" "$branch_purpose"
fi

# Step 10: Build and output final JSON
system_message=""
for msg in "${messages[@]+${messages[@]}}"; do
  if [[ -n "$system_message" ]]; then
    system_message="${system_message}"$'\n'"${msg}"
  else
    system_message="$msg"
  fi
done

if [[ -n "$system_message" ]]; then
  jq -n --arg msg "$system_message" '{"continue": true, "systemMessage": $msg}'
else
  jq -n '{"continue": true}'
fi

exit 0
