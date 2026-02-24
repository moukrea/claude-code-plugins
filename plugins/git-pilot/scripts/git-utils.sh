#!/usr/bin/env bash
set -euo pipefail

# Git utility functions for git-pilot plugin.
# Sourced by hook scripts — do not set SCRIPT_DIR/PLUGIN_ROOT here.

is_git_repo() {
  git rev-parse --git-dir >/dev/null 2>&1
}

get_current_branch() {
  git branch --show-current 2>/dev/null
}

has_uncommitted_changes() {
  [[ -n "$(git status --porcelain 2>/dev/null)" ]]
}

get_default_branch() {
  local config="$1"
  echo "$config" | jq -r '.git.defaultBranch // "main"'
}

is_on_default_branch() {
  local config="$1"
  local current default_branch
  current=$(get_current_branch)
  default_branch=$(get_default_branch "$config")
  [[ "$current" == "$default_branch" ]]
}

has_remote() {
  [[ -n "$(git remote 2>/dev/null)" ]]
}

sanitize_branch_name() {
  local name="$1"
  echo "$name" | sed 's/[^a-zA-Z0-9._/-]//g'
}

is_detached_head() {
  [[ -z "$(git branch --show-current 2>/dev/null)" ]] && git rev-parse HEAD >/dev/null 2>&1
}

get_branch_tracking_status() {
  local branch="$1"
  local remote_name="$2"
  local remote_branch="${remote_name}/${branch}"

  # Check if remote branch exists
  if ! git rev-parse --verify "$remote_branch" >/dev/null 2>&1; then
    echo "no-remote"
    return
  fi

  local local_ref remote_ref base_ref
  local_ref=$(git rev-parse "$branch" 2>/dev/null)
  remote_ref=$(git rev-parse "$remote_branch" 2>/dev/null)
  base_ref=$(git merge-base "$branch" "$remote_branch" 2>/dev/null || true)

  if [[ "$local_ref" == "$remote_ref" ]]; then
    echo "up-to-date"
  elif [[ "$local_ref" == "$base_ref" ]]; then
    local behind_count
    behind_count=$(git rev-list --count "${branch}..${remote_branch}" 2>/dev/null)
    echo "behind:${behind_count}"
  elif [[ "$remote_ref" == "$base_ref" ]]; then
    local ahead_count
    ahead_count=$(git rev-list --count "${remote_branch}..${branch}" 2>/dev/null)
    echo "ahead:${ahead_count}"
  else
    local ahead_count behind_count
    ahead_count=$(git rev-list --count "${remote_branch}..${branch}" 2>/dev/null)
    behind_count=$(git rev-list --count "${branch}..${remote_branch}" 2>/dev/null)
    echo "diverged:${ahead_count}:${behind_count}"
  fi
}

fetch_with_retry() {
  local remote_name="$1"
  local config="$2"
  local specific_branch="${3:-}"

  local max_retries
  max_retries=$(get_config "$config" '.git.fetchRetries' '2')
  local retry_delay
  retry_delay=$(get_config "$config" '.git.fetchRetryDelaySec' '3')

  local fetch_args="$remote_name"
  if [[ -n "$specific_branch" ]]; then
    fetch_args="$remote_name $specific_branch"
  fi

  local attempt=0
  local last_error=""

  while (( attempt <= max_retries )); do
    # shellcheck disable=SC2086 # Intentional word splitting: fetch_args may contain "remote branch"
    if git fetch $fetch_args 2>/dev/null; then
      return 0
    fi

    # shellcheck disable=SC2086 # Intentional word splitting: fetch_args may contain "remote branch"
    last_error=$(git fetch $fetch_args 2>&1 || true)
    attempt=$((attempt + 1))

    if (( attempt <= max_retries )); then
      sleep "$retry_delay"
    fi
  done

  # All retries exhausted
  echo "$last_error" >&2
  return 1
}

derive_branch_purpose() {
  local branch_name="$1"

  # Strip type prefix (e.g., "feat/", "fix/")
  local description
  # shellcheck disable=SC2001 # sed regex not directly replaceable with ${var//pattern/replace}
  description=$(echo "$branch_name" | sed 's|^[^/]*/||')

  # Convert kebab-case/snake_case to words
  description=$(echo "$description" | tr '-' ' ' | tr '_' ' ')

  echo "$description"
}

# Auto-stash uncommitted changes on branch switch.
# Records the stash ref in session state for later restoration.
# Returns 0 on success, 1 if nothing to stash or stash push fails.
auto_stash() {
  local current_branch="$1"
  local session_id="$2"

  if ! has_uncommitted_changes; then
    return 1  # Nothing to stash
  fi

  local stash_msg="git-pilot auto-stash on ${current_branch}"
  if git stash push -m "$stash_msg" >/dev/null 2>&1; then
    local stash_ref
    stash_ref=$(git stash list --format='%gd' | head -1)

    # Record in session state
    if [[ -n "$session_id" ]]; then
      local state_file
      state_file=$(get_state_file "$session_id")
      # shellcheck disable=SC2016 # $ref, $branch, $msg are jq variables, not shell variables
      update_state "$state_file" \
        --arg ref "$stash_ref" \
        --arg branch "$current_branch" \
        --arg msg "$stash_msg" \
        '.stashRefs += [{ref: $ref, branch: $branch, message: $msg, createdAt: (now | todate)}]'
    fi

    return 0
  fi

  return 1
}

# Auto-restore a previously stashed set of changes when switching back to a branch.
# Looks up the stash by branch in session state, finds the current stash index
# by message, and pops it. On success, removes the entry from state.
# Returns 0 on success, 1 if no stash found, session_id is empty, or pop fails.
auto_restore_stash() {
  local target_branch="$1"
  local session_id="$2"

  if [[ -z "$session_id" ]]; then
    return 1
  fi

  local state_file
  state_file=$(get_state_file "$session_id")
  local state
  state=$(read_state "$state_file")

  # Find stash for this branch
  local stash_ref
  # shellcheck disable=SC2016 # $branch is a jq variable, not a shell variable
  stash_ref=$(echo "$state" | jq -r \
    --arg branch "$target_branch" \
    '.stashRefs[] | select(.branch == $branch) | .ref' | head -1)

  if [[ -z "$stash_ref" ]] || [[ "$stash_ref" == "null" ]]; then
    return 1  # No stash for this branch
  fi

  # Find the stash index by message (stash indices shift as stashes are added/removed)
  local stash_msg
  # shellcheck disable=SC2016 # $branch is a jq variable, not a shell variable
  stash_msg=$(echo "$state" | jq -r \
    --arg branch "$target_branch" \
    '.stashRefs[] | select(.branch == $branch) | .message' | head -1)

  local stash_index
  stash_index=$(git stash list --format='%gd %s' | grep "$stash_msg" | head -1 | cut -d' ' -f1)

  if [[ -n "$stash_index" ]]; then
    if git stash pop "$stash_index" >/dev/null 2>&1; then
      # shellcheck disable=SC2016 # $branch is a jq variable, not a shell variable
      # Remove from state on successful pop
      update_state "$state_file" \
        --arg branch "$target_branch" \
        '.stashRefs = [.stashRefs[] | select(.branch != $branch)]'
      return 0
    fi
  fi

  return 1
}
