# Task 002: State Schema Extension

## Status
done

## Dependencies
- 001-config-schema (needs the v2 config schema so that `session-start.sh` can read `git.autoFetch` and other new keys via `get_config()` when calling `init_state()` with new arguments)

## Spec References
- spec/01-config-and-state.md

## Scope
Extend the session state library (`state.sh`) to support the v2 state schema. This means updating `init_state()` to accept five arguments (adding `base_branch` and `branch_purpose`), emitting all new fields in the initial state JSON, and updating `update_state()` to support extra `jq` arguments (e.g., `--arg key val`) passed before the filter. The `read_state()` function is also updated to validate JSON with a fallback.

## Acceptance Criteria
- [x] `init_state()` accepts 5 parameters: `session_id`, `working_branch?`, `previous_branch?`, `base_branch?`, `branch_purpose?`. Parameters 4-5 default to empty string when omitted.
- [x] The initial state JSON produced by `init_state()` contains all v2 fields: `sessionId`, `startTime`, `workingBranch`, `previousBranch`, `headAtStart`, `baseBranch`, `branchPurpose`, `changeCount` (0), `lastCommitAt` (null), `modifiedFiles` ([]), `remoteSkipped` (false), `lastFetchAt` (null), `isAgent` (false), `agentRole` (null), `activeWorktrees` ([]), `stashRefs` ([]).
- [x] `update_state()` supports variadic `jq` arguments: signature is `update_state state_file [jq_args...] jq_filter`, where all arguments after `state_file` are passed to `jq "$@"`.
- [x] `read_state()` returns `{}` if the file is missing or if it contains invalid JSON.
- [x] Calling `init_state()` with only 3 arguments (v1 style) still works correctly, with `baseBranch`, `branchPurpose` defaulting to empty strings and all new array/object fields initialized properly.
- [x] `write_state()` and `cleanup_state()` are unchanged.

## Implementation Notes

### `init_state()` -- updated 5-argument signature

Replace the current `init_state()` function body. The new version from spec Section 4.2:

```bash
init_state() {
  local session_id="$1" working_branch="${2:-}" previous_branch="${3:-}"
  local base_branch="${4:-}" branch_purpose="${5:-}"
  local state_file head_at_start=""
  state_file=$(get_state_file "$session_id")
  if command -v git >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
    head_at_start=$(git rev-parse HEAD 2>/dev/null || true)
  fi
  local content
  content=$(jq -n \
    --arg sid "$session_id" --arg start "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg wb "$working_branch" --arg pb "$previous_branch" \
    --arg head "$head_at_start" --arg bb "$base_branch" --arg bp "$branch_purpose" \
    '{ sessionId:$sid, startTime:$start, workingBranch:$wb, previousBranch:$pb,
       headAtStart:$head, baseBranch:$bb, branchPurpose:$bp, changeCount:0,
       lastCommitAt:null, modifiedFiles:[], remoteSkipped:false, lastFetchAt:null,
       isAgent:false, agentRole:null, activeWorktrees:[], stashRefs:[] }')
  write_state "$state_file" "$content"
}
```

Key changes from v1:
- Two new local variables: `base_branch="${4:-}"` and `branch_purpose="${5:-}"`
- Two new `--arg` flags to `jq -n`: `--arg bb "$base_branch"` and `--arg bp "$branch_purpose"`
- Seven new fields in the JSON template: `baseBranch:$bb`, `branchPurpose:$bp`, `lastFetchAt:null`, `isAgent:false`, `agentRole:null`, `activeWorktrees:[]`, `stashRefs:[]`

### `update_state()` -- variadic jq arguments

Replace the current `update_state()` function. The v2 version uses `shift` to consume `state_file` and then passes all remaining arguments (`"$@"`) directly to `jq`:

```bash
update_state() {
  local state_file="$1"; shift
  local current; current=$(read_state "$state_file")
  local updated; updated=$(echo "$current" | jq "$@")
  write_state "$state_file" "$updated"
}
```

This enables callers to pass `--arg` flags, for example:
```bash
update_state "$state_file" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.lastFetchAt = $ts'
```

The v1 signature `update_state state_file jq_filter` still works because `"$@"` with a single argument is just the filter string.

### `read_state()` -- JSON validation guard

Update `read_state()` to validate the content is valid JSON before returning it:

```bash
read_state() {
  local state_file="$1"
  if [[ -f "$state_file" ]]; then
    local content
    content=$(cat "$state_file")
    if echo "$content" | jq empty 2>/dev/null; then
      echo "$content"
    else
      echo "{}"
    fi
  else
    echo "{}"
  fi
}
```

This ensures that a corrupted state file does not crash downstream `jq` pipelines.

### Update function comment headers

Update the comment for `init_state()` to document the 5-parameter signature:
```bash
# Creates the initial session state file.
# Parameters: session_id, working_branch (optional), previous_branch (optional),
#             base_branch (optional), branch_purpose (optional).
```

Update the comment for `update_state()`:
```bash
# Reads the current state, applies a jq filter, and atomically writes back.
# Parameters: state_file, [jq_args...], jq_filter.
```

## Files to Create or Modify
- plugins/git-pilot/scripts/state.sh (modify)
