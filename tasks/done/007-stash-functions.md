# Task 007: Stash Functions

## Status
done

## Dependencies
- 002-state-schema (stash refs stored in session state as `stashRefs` array; uses `get_state_file()`, `read_state()`, `update_state()`)
- 003-git-utils-extensions (appends functions to same git-utils.sh file)

## Spec References
- spec/05-stash-and-robustness.md (sections 1.1-1.5, 1.9)

## Scope
Implement `auto_stash()` and `auto_restore_stash()` functions in `scripts/git-utils.sh`. These functions manage automatic stashing and restoring of uncommitted changes during branch switches, with stash metadata tracked in the session state file's `stashRefs` array.

## Acceptance Criteria
- [x] `auto_stash()` accepts `current_branch` and `session_id`, returns 1 if nothing to stash, 0 on success
- [x] `auto_stash()` calls `git stash push -m "git-pilot auto-stash on ${current_branch}"` and records the ref in session state via `update_state` with jq filter `.stashRefs += [{ref: $ref, branch: $branch, message: $msg, createdAt: (now | todate)}]`
- [x] `auto_restore_stash()` accepts `target_branch` and `session_id`, looks up stash by branch in state using jq, finds current index via `git stash list` grep on message, and pops it
- [x] On successful pop, `auto_restore_stash()` removes the entry from state with `.stashRefs = [.stashRefs[] | select(.branch != $branch)]`
- [x] `auto_restore_stash()` returns 1 if no stash found for branch or if session_id is empty
- [x] Stash data is never lost: `git stash pop` preserves the stash on conflict (atomic apply+drop)
- [x] `normalize_protect_default_branch()` function is added to handle boolean-to-string migration for `git.protectDefaultBranch` config key

## Implementation Notes

### `auto_stash(current_branch, session_id)`

```bash
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

    if [[ -n "$session_id" ]]; then
      local state_file
      state_file=$(get_state_file "$session_id")
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
```

**Note**: The current v1 `update_state()` in `state.sh` only accepts 2 arguments (`state_file`, `jq_filter`). This function passes `--arg` flags, so `update_state()` must be extended (in task 002) to support variadic jq arguments before the filter. The call pattern is: `update_state "$state_file" --arg key val --arg key2 val2 'jq_filter'`. If task 002 is not yet complete, implement the call using inline jq instead:
```bash
local state_file; state_file=$(get_state_file "$session_id")
local current; current=$(read_state "$state_file")
local updated; updated=$(echo "$current" | jq \
  --arg ref "$stash_ref" --arg branch "$current_branch" --arg msg "$stash_msg" \
  '.stashRefs += [{ref: $ref, branch: $branch, message: $msg, createdAt: (now | todate)}]')
write_state "$state_file" "$updated"
```

### `auto_restore_stash(target_branch, session_id)`

Lookup stash ref and message from state by branch using jq:
```bash
stash_ref=$(echo "$state" | jq -r --arg branch "$target_branch" \
  '.stashRefs[] | select(.branch == $branch) | .ref' | head -1)
stash_msg=$(echo "$state" | jq -r --arg branch "$target_branch" \
  '.stashRefs[] | select(.branch == $branch) | .message' | head -1)
```

Then find current index: `git stash list --format='%gd %s' | grep "$stash_msg" | head -1 | cut -d' ' -f1`

Known limitation: stash-by-message lookup is fragile if user manually creates stashes with `"git-pilot auto-stash on "` prefix.

### `normalize_protect_default_branch(value)`

```bash
normalize_protect_default_branch() {
  local value="$1"
  case "$value" in
    true)  echo "warn" ;;
    false) echo "off" ;;
    warn|block|off) echo "$value" ;;
    *) echo "warn" ;;
  esac
}
```

This handles v1 boolean -> v2 string enum migration. Called wherever `git.protectDefaultBranch` is read.

## Files to Create or Modify
- plugins/git-pilot/scripts/git-utils.sh (modify -- add `auto_stash()`, `auto_restore_stash()`, `normalize_protect_default_branch()`)
