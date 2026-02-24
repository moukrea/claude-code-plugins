# Task 010: Hook post-bash.sh Modifications

## Status
done

## Dependencies
- 004-agent-library (uses `is_agent_context()` and `is_operation_agent_restricted()` from `scripts/agent.sh`)

## Spec References
- spec/06-hooks-and-lifecycle.md (sections 5a, 5b)
- spec/05-stash-and-robustness.md (section 4 -- output helpers referenced for message format)

## Scope
Modify the existing `post-bash.sh` script to add two capabilities: (a) agent suppression that skips push prompts for agent contexts where push is restricted, and (b) push rejection detection that intercepts failed `git push` commands and provides recovery options.

## Acceptance Criteria
- [x] Source `agent.sh` and check `is_agent_context "$session_id"` early in the script; if true and `is_operation_agent_restricted "$config" "push"` is true, emit `{"continue": true}` and exit
- [x] After the existing push prompt logic, detect failed `git push` commands by checking `exit_code != 0` and stderr matching `rejected|failed to push|non-fast-forward`
- [x] On push rejection, emit a 4-option message: pull+rebase, force-push-with-lease, pull+merge, cancel
- [x] The push rejection message format is: `"[git-pilot] Push rejected -- remote '${remote_name}/${current_branch}' has new commits. Prompt the user:\n1. Pull and rebase...\n2. Force push with lease...\n3. Pull and merge...\n4. Cancel"`
- [x] Session ID is extracted from input JSON via `jq -r '.session_id // empty'`
- [x] Exit code, stdout, and stderr are extracted from `.tool_result.exitCode`, `.tool_result.stdout`, `.tool_result.stderr` respectively

## Implementation Notes

### Agent suppression -- insert after loading config, before the push check

The v1 `post-bash.sh` currently only checks for `git commit` commands. Add agent check at the top of the script logic:

```bash
source "$SCRIPT_DIR/agent.sh"

# Extract session_id (v1 does not extract this -- add it)
session_id=$(echo "$input" | jq -r '.session_id // empty')

if is_agent_context "$session_id"; then
  if is_operation_agent_restricted "$config" "push"; then
    echo '{"continue": true}'
    exit 0
  fi
fi
```

This goes after `config=$(load_config "$cwd")` and before any push-related logic.

### Push rejection detection -- insert after the existing push prompt block

The v1 script only looks at `git commit` commands. Add a new block to detect push failures:

```bash
exit_code=$(echo "$input" | jq -r '.tool_result.exitCode // 0')
stdout=$(echo "$input" | jq -r '.tool_result.stdout // empty')
stderr=$(echo "$input" | jq -r '.tool_result.stderr // empty')

if echo "$command" | grep -qE 'git\s+push' && [[ "$exit_code" != "0" ]]; then
  if echo "$stderr" | grep -qiE 'rejected|failed to push|non-fast-forward'; then
    current_branch=$(get_current_branch)
    remote_name=$(get_config "$config" '.remote.defaultName' 'origin')
    message="[git-pilot] Push rejected -- remote '${remote_name}/${current_branch}' has new commits. Prompt the user:
1. Pull and rebase, then retry push (git pull --rebase && git push)
2. Force push with lease (git push --force-with-lease)
3. Pull and merge (git pull)
4. Cancel"
    jq -n --arg msg "$message" '{"continue": true, "systemMessage": $msg}'
    exit 0
  fi
fi
```

The `command` variable is already extracted in v1 as `$(echo "$input" | jq -r '.tool_input.command // empty')`. The `exit_code`, `stdout`, `stderr` are new extractions from the PostToolUse input payload.

### Broadening command detection

The v1 `post-bash.sh` currently early-exits if the command does not match `git\s+commit`. This guard must be relaxed to also process `git push` commands. Change the early filter from:
```bash
if [[ -z "$command" ]] || ! echo "$command" | grep -qE 'git\s+commit'; then
```
to:
```bash
if [[ -z "$command" ]] || ! echo "$command" | grep -qE 'git\s+(commit|push)'; then
```

## Files to Create or Modify
- plugins/git-pilot/scripts/post-bash.sh (modify -- add agent suppression, push rejection detection, broaden command filter)

## Validation Notes

**PASS**: All acceptance criteria satisfied. The missing `stdout` extraction line has been added to `post-bash.sh` between `exit_code` and `stderr`. Script passes `bash -n` syntax check and `shellcheck --severity=warning` (only SC2034 for the intentionally-unused `stdout` variable).
