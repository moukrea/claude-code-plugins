# Task 011: Hook post-write.sh Modifications

## Status
done

## Dependencies
- 004-agent-library (uses `is_agent_context()` from `scripts/agent.sh`)

## Spec References
- spec/06-hooks-and-lifecycle.md (section 6)

## Scope
Modify the existing `post-write.sh` script to add agent suppression. In agent contexts, file change tracking still runs (changeCount increment, modifiedFiles append), but the threshold-reached commit suggestion message is suppressed -- the script exits before emitting the system message.

## Acceptance Criteria
- [x] Source `agent.sh` at the top alongside existing config/state sources
- [x] Extract `session_id` from input (already done in v1 as `session_id=$(echo "$input" | jq -r '.session_id')`)
- [x] After file tracking state updates are written (changeCount increment, modifiedFiles append), check `is_agent_context "$session_id"` and exit 0 before the threshold message block
- [x] File change tracking (changeCount, modifiedFiles) continues to work for agents -- only the commit suggestion message is suppressed
- [x] Non-agent behavior is completely unchanged

## Implementation Notes

### Agent suppression -- insert after state write, before threshold check

The v1 `post-write.sh` flow is:
1. Read input, load config, check `autoCommit.enabled`
2. Increment `changeCount`, append to `modifiedFiles`, write state
3. Check if `change_count >= threshold` -> emit message

The agent check goes between steps 2 and 3:

```bash
source "$SCRIPT_DIR/agent.sh"

# ... (existing tracking code: increment changeCount, append modifiedFiles, write_state) ...

# Agent suppression: track changes but suppress commit suggestion
if is_agent_context "$session_id"; then
  exit 0
fi

# ... (existing threshold check and message emission) ...
```

The `source` line for `agent.sh` should be added at the top of the file alongside the existing `source` statements:

```bash
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/state.sh"
source "$SCRIPT_DIR/agent.sh"  # NEW
```

Per spec/06 section 6: "Still track file changes but suppress commit suggestion messages for agents."

## Files to Create or Modify
- plugins/git-pilot/scripts/post-write.sh (modify -- add agent.sh source, agent suppression after tracking)
