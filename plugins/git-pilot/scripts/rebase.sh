#!/usr/bin/env bash
set -euo pipefail

# Rebase and conflict resolution library for git-pilot plugin.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=git-utils.sh
source "$SCRIPT_DIR/git-utils.sh"

# Detects how many commits the base branch has advanced since the feature
# branch diverged.
#
# Arguments:
#   $1 - current branch name
#   $2 - base branch name
#   $3 - remote name
#
# Output (stdout):
#   "no-drift"            - base branch has no new commits
#   "drifted:N"           - base branch has N new commits
#   "no-common-ancestor"  - cannot determine merge base
#
# Returns: 0 on success, 1 on fetch failure
get_base_branch_drift() {
  local current_branch="$1"
  local base_branch="$2"
  local remote_name="$3"
  local remote_base="${remote_name}/${base_branch}"

  # Fetch latest base branch state
  git fetch "$remote_name" "$base_branch" 2>/dev/null || return 1

  # Find the merge base between current branch and remote base
  local merge_base
  merge_base=$(git merge-base "$current_branch" "$remote_base" 2>/dev/null || true)

  if [[ -z "$merge_base" ]]; then
    echo "no-common-ancestor"
    return
  fi

  # Count commits on base branch since the branch point
  local drift_count
  drift_count=$(git rev-list --count "${merge_base}..${remote_base}" 2>/dev/null)

  if [[ "$drift_count" -eq 0 ]]; then
    echo "no-drift"
  else
    echo "drifted:${drift_count}"
  fi
}

# Performs a rebase onto a target branch with clean error categorization.
#
# Arguments:
#   $1 - target branch to rebase onto (e.g., origin/main)
#
# Output (stdout):
#   "success"              - rebase completed cleanly
#   "conflict"             - rebase stopped due to merge conflicts
#   "error:dirty-worktree" - working tree has uncommitted changes
#   "error:<output>"       - rebase failed for another reason
#
# Returns: 0 on success, 1 on conflict or error
attempt_rebase() {
  local target_branch="$1"

  # Ensure clean working tree
  if has_uncommitted_changes; then
    echo "error:dirty-worktree"
    return 1
  fi

  # Attempt rebase
  local rebase_output
  if rebase_output=$(git rebase "$target_branch" 2>&1); then
    echo "success"
    return 0
  else
    # Check if it's a conflict
    if git diff --name-only --diff-filter=U 2>/dev/null | head -1 | grep -q .; then
      echo "conflict"
      return 1
    else
      echo "error:${rebase_output}"
      return 1
    fi
  fi
}

# Returns a JSON array describing each conflicting file during a rebase.
#
# Output (stdout): JSON array of objects with fields:
#   file            - relative file path
#   type            - "both-modified", "deleted-by-us", or "deleted-by-them"
#   conflictRegions - count of <<<<<<< markers in the file
#
# Returns: 0
get_conflict_details() {
  local conflict_files
  conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null)

  if [[ -z "$conflict_files" ]]; then
    echo "[]"
    return
  fi

  local result="["
  local first=true

  while IFS= read -r file; do
    local ours_exists theirs_exists
    ours_exists=$(git ls-files --stage "$file" 2>/dev/null | grep -c "^[0-9]* [a-f0-9]* 2" || echo "0")
    theirs_exists=$(git ls-files --stage "$file" 2>/dev/null | grep -c "^[0-9]* [a-f0-9]* 3" || echo "0")

    local conflict_type="both-modified"
    if [[ "$ours_exists" == "0" ]]; then
      conflict_type="deleted-by-us"
    elif [[ "$theirs_exists" == "0" ]]; then
      conflict_type="deleted-by-them"
    fi

    local marker_count=0
    if [[ -f "$file" ]]; then
      marker_count=$(grep -c '^<<<<<<< ' "$file" 2>/dev/null || echo "0")
    fi

    if [[ "$first" == "true" ]]; then
      first=false
    else
      result+=","
    fi
    result+=$(jq -n \
      --arg f "$file" \
      --arg t "$conflict_type" \
      --argjson m "$marker_count" \
      '{file: $f, type: $t, conflictRegions: $m}')
  done <<< "$conflict_files"

  result+="]"
  echo "$result"
}

# Returns a recommendation string for a given conflict type and region count.
#
# Arguments:
#   $1 - conflict type: "both-modified", "deleted-by-us", or "deleted-by-them"
#   $2 - number of conflict regions (integer)
#
# Output (stdout): recommendation string
get_conflict_recommendation() {
  local conflict_type="$1"
  local regions="$2"

  case "$conflict_type" in
    deleted-by-us)
      echo "File was deleted locally but modified on base. If the deletion was intentional, accept ours (delete). Otherwise, accept theirs." ;;
    deleted-by-them)
      echo "File was deleted on base but modified locally. If your changes are still needed, accept ours. Otherwise, accept theirs (delete)." ;;
    both-modified)
      if [[ "$regions" -le 1 ]]; then
        echo "Single conflict region -- likely a small overlap. Manual review recommended."
      elif [[ "$regions" -gt 3 ]]; then
        echo "Multiple conflict regions -- significant concurrent changes. Manual review required."
      else
        echo "Manual review recommended."
      fi
      ;;
  esac
}

# Detects whether a force push is required after rebase.
#
# Arguments:
#   $1 - branch name
#   $2 - remote name
#
# Returns:
#   0 - force push is needed (remote tracking branch exists, refs differ,
#       and remote is not an ancestor of local)
#   1 - normal push is fine
needs_force_push() {
  local branch="$1"
  local remote_name="$2"

  # Check if remote tracking branch exists
  if ! git rev-parse --verify "${remote_name}/${branch}" >/dev/null 2>&1; then
    return 1  # No remote branch, normal push works
  fi

  # Check if local and remote have diverged after rebase
  local local_ref remote_ref
  local_ref=$(git rev-parse "$branch" 2>/dev/null)
  remote_ref=$(git rev-parse "${remote_name}/${branch}" 2>/dev/null)

  if [[ "$local_ref" != "$remote_ref" ]]; then
    # Check if remote is NOT an ancestor of local (diverged, not just ahead)
    if ! git merge-base --is-ancestor "$remote_ref" "$local_ref" 2>/dev/null; then
      return 0  # Needs force push
    fi
  fi

  return 1
}
