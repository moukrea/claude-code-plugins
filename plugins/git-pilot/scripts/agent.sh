#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=state.sh
source "$SCRIPT_DIR/state.sh"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

# Detects whether the current session is running as a spawned agent.
#
# Detection order:
#   1. CLAUDE_SPAWNED_BY env var non-empty (primary, set by Claude Code)
#   2. Session state .isAgent == true (fallback for resilience)
#
# Parameters:
#   $1 (optional): session ID for state-file fallback lookup
#
# Returns:
#   0 if agent context detected, 1 otherwise
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

# Checks whether a named operation should be suppressed for agents.
#
# Returns 0 (restricted) when agentTeams.suppressPromptsForAgents is true
# AND the operation name appears in the agentTeams.orchestratorOnly array.
#
# Parameters:
#   $1: config JSON (the merged config object from load_config())
#   $2: operation name string -- one of "push", "mr", "branch-prompt",
#       "auto-commit", "rebase", "session-summary", "branch-freshness"
#
# Returns:
#   0 if the operation is restricted (agent should skip it)
#   1 if the operation is not restricted
is_operation_agent_restricted() {
  local config="$1"
  local operation="$2"

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
