# Task 005: Rebase Library

## Status
done

## Dependencies
- 001-config-schema (needs `get_config()` for `rebase.autoRebaseBeforePush`, `rebase.conflictStrategy`, `rebase.allowForcePush`, and `git.defaultBranch` config keys)
- 003-git-utils-extensions (needs `get_branch_tracking_status()`, `fetch_with_retry()`, `has_uncommitted_changes()` from `scripts/git-utils.sh`)

## Spec References
- spec/03-rebase-and-conflicts.md (sections 1 through 5)

## Scope
Implement `scripts/rebase.sh` containing four functions: `get_base_branch_drift()` (detects how many commits the base branch has advanced since the feature branch diverged), `attempt_rebase()` (performs a rebase onto a target branch with clean error categorization), `get_conflict_details()` (returns a JSON array of conflicting files with type and region count), and `needs_force_push()` (detects whether a force push is required after rebase). Also adds the `rebase.*` default config keys. This task does NOT wire these functions into hook scripts; it provides the library that hooks will call.

## Acceptance Criteria
- [x] `plugins/git-pilot/scripts/rebase.sh` exists, starts with `#!/usr/bin/env bash` and `set -euo pipefail`, sources `git-utils.sh` and `config.sh` from the same directory
- [x] `get_base_branch_drift()` returns `no-drift`, `drifted:N`, or `no-common-ancestor` with correct exit codes
- [x] `attempt_rebase()` returns `success` (exit 0), `conflict` (exit 1), `error:dirty-worktree` (exit 1), or `error:<output>` (exit 1)
- [x] `get_conflict_details()` returns a JSON array with objects containing `file` (string), `type` (one of `both-modified`, `deleted-by-us`, `deleted-by-them`), and `conflictRegions` (integer)
- [x] `needs_force_push()` returns 0 when remote tracking branch exists, refs differ, and remote is not an ancestor of local; returns 1 otherwise
- [x] Config keys `rebase.autoRebaseBeforePush`, `rebase.conflictStrategy`, and `rebase.allowForcePush` are read via `get_config()` (already defined in `defaults/config.json` by task 001)
- [x] A helper function `get_conflict_recommendation()` returns the correct recommendation string per conflict type and region count

## Implementation Notes

### File: `plugins/git-pilot/scripts/rebase.sh`

Source `git-utils.sh` (for `has_uncommitted_changes()`) and `config.sh` (for `get_config()`).

**`get_base_branch_drift()` function** (spec section 1.1):
```bash
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
```

Parameters: `$1` = current branch name, `$2` = base branch name, `$3` = remote name.
Return values: `no-drift` | `drifted:N` | `no-common-ancestor`.

**Base branch determination** (spec section 1.3) -- callers resolve the base branch in this order:
1. Session state `baseBranch` field
2. `git config branch.${current}.merge` stripped of `refs/heads/`
3. `git.defaultBranch` from config (default: `"main"`)

**`attempt_rebase()` function** (spec section 2.1):
```bash
attempt_rebase() {
  local target_branch="$1"  # Branch to rebase onto (e.g., origin/main)

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
```

Parameters: `$1` = target branch to rebase onto (e.g., `origin/main`).
Return values: `success` (exit 0) | `conflict` (exit 1) | `error:dirty-worktree` (exit 1) | `error:<output>` (exit 1).

**`get_conflict_details()` function** (spec section 2.2):
```bash
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
    ours_exists=$(git ls-files --stage "$file" 2>/dev/null | grep "^[0-9]* [a-f0-9]* 2" | wc -l | tr -d ' ')
    theirs_exists=$(git ls-files --stage "$file" 2>/dev/null | grep "^[0-9]* [a-f0-9]* 3" | wc -l | tr -d ' ')

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
```

Output JSON schema:
```json
[
  {"file": "src/auth.ts", "type": "both-modified", "conflictRegions": 2},
  {"file": "src/utils.ts", "type": "deleted-by-us", "conflictRegions": 0}
]
```

Conflict type detection (spec section 2.2): stage 2 = "ours", stage 3 = "theirs" in `git ls-files --stage`. If stage 2 count is 0: `deleted-by-us`. If stage 3 count is 0: `deleted-by-them`. Otherwise: `both-modified`.

**`get_conflict_recommendation()` helper** (spec section 2.4):
```bash
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
```

**`needs_force_push()` function** (spec section 3.1):
```bash
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
```

Returns 0 (needs force push) when: (1) remote tracking branch exists AND (2) local and remote refs differ AND (3) remote ref is NOT an ancestor of local ref. Returns 1 otherwise.

**`rebase.conflictStrategy` handling** (spec section 2.5) -- callers use this logic:

| Strategy | Behavior |
|----------|----------|
| `"prompt"` | Emit conflict details and prompt user (default) |
| `"abort"` | `git rebase --abort`. Emit: `"[git-pilot] Rebase aborted due to conflicts. Push without rebase."` |
| `"merge-fallback"` | `git rebase --abort && git merge ${target}`. If merge also conflicts, fall back to `"prompt"` |

**`rebase.allowForcePush` handling** (spec section 3.2) -- callers use this logic:

| Setting | Behavior |
|---------|----------|
| `"ask"` | Emit: `"[git-pilot] Rebase rewrote history. Force push required. Prompt the user: force push (git push --force-with-lease) or abort."` |
| `"never"` | Emit: `"[git-pilot] Rebase rewrote history but force push is disabled. The rebase changes are local only. Push manually if needed."` |
| `"always"` | `git push --force-with-lease` automatically. Emit: `"[git-pilot] Force-pushed '${branch}' to '${remote}/${branch}' after rebase."` |

Always use `--force-with-lease` (never bare `--force`).

### Config keys (defined in `defaults/config.json` by task 001):
Config keys are already defined in `defaults/config.json` by task 001. This task only needs to READ them via `get_config()`.
```json
{
  "rebase": {
    "autoRebaseBeforePush": true,
    "conflictStrategy": "prompt",
    "allowForcePush": "ask"
  }
}
```

## Files to Create or Modify
- plugins/git-pilot/scripts/rebase.sh (new)

## Validation Notes

**PASS**: All acceptance criteria met. Source statements for `config.sh` and `git-utils.sh` added with `SCRIPT_DIR` definition, matching the pattern in `agent.sh` and `worktree.sh`. Verified with `bash -n` and `shellcheck --severity=warning`.
