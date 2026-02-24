#!/usr/bin/env bash
set -euo pipefail

# Worktree management library for git-pilot.
# Provides functions to create, remove, list, and merge git worktrees,
# with a JSON registry for tracking active worktrees.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "$SCRIPT_DIR/config.sh"

# Registry file lives inside the git directory (works correctly in worktree contexts).
WORKTREE_REGISTRY="$(git rev-parse --git-dir 2>/dev/null)/git-pilot-worktrees.json"

# Creates a git worktree at the configured base path with the given branch.
# Parameters:
#   $1 - config JSON (from load_config)
#   $2 - branch name to create
#   $3 - base branch to create from
#   $4 - session ID (optional)
# Returns: echoes the worktree path on stdout on success.
# On failure: writes "error:<git output>" to stderr and returns 1.
create_worktree() {
  local config="$1"
  local branch_name="$2"
  local base_branch="$3"
  local session_id="${4:-}"

  local project_name
  project_name=$(basename "$(git rev-parse --show-toplevel)")

  local base_path
  base_path=$(get_config "$config" '.worktree.basePath' "../{{project}}-worktrees")
  base_path="${base_path//\{\{project\}\}/$project_name}"

  local dir_name
  dir_name=$(echo "$branch_name" | tr '/' '-')
  local worktree_path="${base_path}/${dir_name}"

  mkdir -p "$(dirname "$worktree_path")"

  local output
  if output=$(git worktree add "$worktree_path" -b "$branch_name" "$base_branch" 2>&1); then
    register_worktree "$worktree_path" "$branch_name" "$base_branch" "$session_id"
    echo "$worktree_path"
    return 0
  else
    echo "error:${output}" >&2
    return 1
  fi
}

# Removes a git worktree and unregisters it from the registry.
# Parameters:
#   $1 - worktree path
#   $2 - "true" for force removal (optional, default "false")
# Returns: 0 on success, 1 on failure.
remove_worktree() {
  local worktree_path="$1"
  local force="${2:-false}"

  local flags=""
  if [[ "$force" == "true" ]]; then
    flags="--force"
  fi

  # shellcheck disable=SC2086
  if git worktree remove "$worktree_path" $flags 2>/dev/null; then
    unregister_worktree "$worktree_path"
    return 0
  else
    return 1
  fi
}

# Adds a worktree entry to the JSON registry using atomic writes.
# Parameters:
#   $1 - worktree path
#   $2 - branch name
#   $3 - base branch
#   $4 - session ID (optional)
register_worktree() {
  local path="$1"
  local branch="$2"
  local base_branch="$3"
  local session_id="${4:-}"

  local registry
  if [[ -f "$WORKTREE_REGISTRY" ]]; then
    registry=$(cat "$WORKTREE_REGISTRY")
  else
    registry='{"worktrees":[]}'
  fi

  local entry
  entry=$(jq -n \
    --arg p "$path" \
    --arg b "$branch" \
    --arg bb "$base_branch" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sid "$session_id" \
    '{path:$p, branch:$b, baseBranch:$bb, createdAt:$ts, createdBy:$sid, status:"active"}')

  registry=$(echo "$registry" | jq --argjson e "$entry" '.worktrees += [$e]')

  local tmp="${WORKTREE_REGISTRY}.tmp.$$"
  echo "$registry" > "$tmp" && mv "$tmp" "$WORKTREE_REGISTRY"
}

# Removes a worktree entry from the JSON registry using atomic writes.
# Parameters:
#   $1 - worktree path to remove
unregister_worktree() {
  local path="$1"
  if [[ ! -f "$WORKTREE_REGISTRY" ]]; then
    return
  fi
  local registry
  registry=$(cat "$WORKTREE_REGISTRY")
  registry=$(echo "$registry" | jq --arg p "$path" \
    '.worktrees = [.worktrees[] | select(.path != $p)]')
  local tmp="${WORKTREE_REGISTRY}.tmp.$$"
  echo "$registry" > "$tmp" && mv "$tmp" "$WORKTREE_REGISTRY"
}

# Returns the full registry JSON, or an empty structure if no registry exists.
# Returns: JSON string on stdout.
list_worktrees() {
  if [[ -f "$WORKTREE_REGISTRY" ]]; then
    cat "$WORKTREE_REGISTRY"
  else
    echo '{"worktrees":[]}'
  fi
}

# Merges a worktree branch into the target branch.
# If worktree.cleanupOnMerge is true, removes the worktree and deletes the branch after merge.
# Parameters:
#   $1 - worktree path
#   $2 - target branch to merge into
#   $3 - config JSON (from load_config)
# Returns: echoes "success" (exit 0), "conflict" (exit 1), or "error:cannot-determine-branch" (exit 1).
merge_worktree_branch() {
  local worktree_path="$1"
  local target_branch="$2"
  local config="$3"

  local wt_branch
  wt_branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null)

  if [[ -z "$wt_branch" ]]; then
    echo "error:cannot-determine-branch"
    return 1
  fi

  git checkout "$target_branch" 2>/dev/null || return 1

  local merge_output
  # shellcheck disable=SC2034 # merge_output captures stderr; only the exit code is used
  if merge_output=$(git merge "$wt_branch" --no-edit 2>&1); then
    echo "success"
    local cleanup
    cleanup=$(get_config "$config" '.worktree.cleanupOnMerge' 'true')
    if [[ "$cleanup" == "true" ]]; then
      remove_worktree "$worktree_path" "false"
      git branch -d "$wt_branch" 2>/dev/null || true
    fi
    return 0
  else
    echo "conflict"
    return 1
  fi
}
