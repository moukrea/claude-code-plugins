# Task 004: Agent Detection Library

## Status
done

## Dependencies
- 001-config-schema (needs `get_config()` for `agentTeams.suppressPromptsForAgents` and `agentTeams.orchestratorOnly` config keys)
- 002-state-schema (needs `get_state_file()`, `read_state()`, `update_state()` for reading the `isAgent` and `agentRole` session state fields)

## Spec References
- spec/04-agent-and-worktree.md (sections 1.1 through 1.6)

## Scope
Implement `scripts/agent.sh` containing two core detection functions: `is_agent_context()` (detects whether the current session is a spawned agent via `CLAUDE_SPAWNED_BY` env var or session state `.isAgent` field) and `is_operation_agent_restricted()` (checks whether a named operation should be suppressed for agents based on `agentTeams.suppressPromptsForAgents` and `agentTeams.orchestratorOnly` config keys). This task does NOT modify existing hook scripts (that is integration work for a later task); it provides the library functions those hooks will source.

## Acceptance Criteria
- [x] `plugins/git-pilot/scripts/agent.sh` exists, starts with `#!/usr/bin/env bash` and `set -euo pipefail`, sources `state.sh` from the same directory
- [x] `is_agent_context()` returns 0 when `CLAUDE_SPAWNED_BY` env var is non-empty (primary detection)
- [x] `is_agent_context()` returns 0 when session state `.isAgent == true` (fallback detection via `get_state_file` + `read_state` + jq)
- [x] `is_agent_context()` returns 1 when neither condition is met
- [x] `is_operation_agent_restricted()` returns 0 (restricted) when `agentTeams.suppressPromptsForAgents` is `true` AND the operation name appears in `agentTeams.orchestratorOnly` array
- [x] `is_operation_agent_restricted()` returns 1 (not restricted) when `agentTeams.suppressPromptsForAgents` is `false` or the operation is not in the `orchestratorOnly` list
- [x] Config keys `agentTeams.suppressPromptsForAgents` and `agentTeams.orchestratorOnly` are read via `get_config()` (already defined in `defaults/config.json` by task 001)

## Implementation Notes

### File: `plugins/git-pilot/scripts/agent.sh`

Source `state.sh` for access to `get_state_file()` and `read_state()`. Source `config.sh` for `get_config()`.

**`is_agent_context()` function** (spec section 1.1):
```bash
is_agent_context() {
  # Primary: check Claude Code spawned-by indicator
  if [[ -n "${CLAUDE_SPAWNED_BY:-}" ]]; then
    return 0
  fi

  # Secondary: check for agent role in session state
  local session_id="${1:-}"
  if [[ -n "$session_id" ]]; then
    local state_file
    state_file=$(get_state_file "$session_id")
    local state
    state=$(read_state "$state_file")
    local is_agent
    is_agent=$(echo "$state" | jq -r '.isAgent // false')
    if [[ "$is_agent" == "true" ]]; then
      return 0
    fi
  fi

  return 1
}
```

Parameters:
- `$1` (optional): session ID for state-file fallback

Detection order:
1. `CLAUDE_SPAWNED_BY` env var non-empty (primary, set by Claude Code)
2. Session state `.isAgent == true` (fallback for resilience)

**`is_operation_agent_restricted()` function** (spec section 1.2):
```bash
is_operation_agent_restricted() {
  local config="$1"
  local operation="$2"  # "push", "mr", "branch-prompt", etc.

  local suppress
  suppress=$(get_config "$config" '.agentTeams.suppressPromptsForAgents' 'true')

  if [[ "$suppress" != "true" ]]; then
    return 1  # Not suppressed
  fi

  # Check if this specific operation is orchestrator-only
  local restricted
  restricted=$(echo "$config" | jq -r --arg op "$operation" \
    '.agentTeams.orchestratorOnly // ["push", "mr"] | map(select(. == $op)) | length')

  if [[ "$restricted" -gt 0 ]]; then
    return 0  # Restricted to orchestrator
  fi

  return 1
}
```

Parameters:
- `$1`: config JSON (the merged config object from `load_config()`)
- `$2`: operation name string -- one of `"push"`, `"mr"`, `"branch-prompt"`, `"auto-commit"`, `"rebase"`, `"session-summary"`, `"branch-freshness"`

The jq filter `.agentTeams.orchestratorOnly // ["push", "mr"]` provides the default array inline, so if the key is missing the defaults apply.

### Prompt suppression pattern (for reference -- hooks will use this in later tasks):
```bash
if is_agent_context "$SESSION_ID" && \
   is_operation_agent_restricted "$CONFIG" "push"; then
  echo '{"continue": true}'
  exit 0
fi
```

### Operations and agent behavior table (spec section 1.6):

| Operation | Orchestrator | Agent |
|-----------|-------------|-------|
| Branch creation prompt | Interactive | Suppressed |
| Push prompt after commit | Interactive | Suppressed |
| MR creation | Interactive | Suppressed |
| Commit validation | Active | Active |
| Auto-commit suggestions | Active | Suppressed |
| Rebase/conflict prompts | Interactive | Suppressed (abort rebase silently) |
| Session summary | Active | Suppressed |
| Branch freshness warnings | Active | Log to state only (no prompt) |

### Config keys (defined in `defaults/config.json` by task 001):
Config keys are already defined in `defaults/config.json` by task 001. This task only needs to READ them via `get_config()`.
```json
{
  "agentTeams": {
    "suppressPromptsForAgents": true,
    "orchestratorOnly": ["push", "mr"]
  }
}
```

## Files to Create or Modify
- plugins/git-pilot/scripts/agent.sh (new)
