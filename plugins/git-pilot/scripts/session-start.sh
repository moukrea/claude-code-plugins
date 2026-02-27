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
  messages+=("[git-pilot] git not installed -- workflow features disabled")
fi

if ! command -v jq >/dev/null 2>&1; then
  messages+=("[git-pilot] jq not installed -- config loading may fail")
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
      messages+=("[git-pilot] Initialized git repo (branch: ${default_branch})")
    else
      messages+=("[git-pilot] git init failed")
    fi
  else
    messages+=("[git-pilot] Not a git repository")
  fi
fi

# Step 6a: Fetch remote (after git init check, before branch detection)
if is_git_repo && has_remote; then
  auto_fetch=$(get_config "$CONFIG" '.git.autoFetch' 'true')
  remote_name=$(get_config "$CONFIG" '.remote.defaultName' 'origin')
  if [[ "$auto_fetch" == "true" ]]; then
    retries=$(get_config "$CONFIG" '.git.fetchRetries' '2')
    if ! fetch_with_retry "$remote_name" "$CONFIG"; then
      messages+=("[git-pilot] Remote fetch failed -- proceeding offline")
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
      messages+=("[git-pilot] Detached HEAD at ${head_sha} (previous branch: ${prev_branch})")
    else
      messages+=("[git-pilot] Detached HEAD at ${head_sha}")
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
          messages+=("[git-pilot] Branch '${current_branch}' fast-forwarded ${behind_count} commit(s)")
        else
          messages+=("[git-pilot] Branch '${current_branch}' is ${behind_count} commit(s) behind remote")
        fi
        ;;
      diverged:*:*)
        IFS=':' read -r _ ahead_count behind_count <<< "$tracking_status"
        messages+=("[git-pilot] Branch '${current_branch}' diverged: ${ahead_count} local, ${behind_count} remote")
        ;;
      ahead:*)
        ahead_count="${tracking_status#ahead:}"
        messages+=("[git-pilot] ${ahead_count} unpushed commit(s) on '${current_branch}'")
        ;;
      # up-to-date and no-remote: no message
    esac
  fi

  # Step 7c: Default branch detection
  auto_create=$(get_config "$CONFIG" '.branch.autoCreate' 'true')

  if [[ "$auto_create" == "true" ]] && [[ "$current_branch" == "$default_branch" ]]; then
    messages+=("[git-pilot] On default branch '${default_branch}'")
  fi
fi

# Step 8: Remote detection (only if we are in a git repo)
if is_git_repo; then
  if ! has_remote; then
    messages+=("[git-pilot] No git remote configured")
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
context_lines=""
for msg in "${messages[@]+${messages[@]}}"; do
  if [[ -n "$context_lines" ]]; then
    context_lines="${context_lines}"$'\n'"${msg}"
  else
    context_lines="$msg"
  fi
done

if [[ -n "$context_lines" ]]; then
  jq -n --arg ctx "$context_lines" '{"continue": true, "additionalContext": $ctx}'
else
  jq -n '{"continue": true}'
fi

exit 0
