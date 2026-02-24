#!/usr/bin/env bats

# Tests for agent.sh: is_agent_context, is_operation_agent_restricted.

load test_helper/common

setup() {
  setup_test_repo
  source_script "config.sh"
  source_script "state.sh"
  source_script "agent.sh"

  # Ensure CLAUDE_SPAWNED_BY is unset by default
  unset CLAUDE_SPAWNED_BY
}

teardown() {
  unset CLAUDE_SPAWNED_BY
  rm -f /tmp/git-pilot-test-agent-*.json
  teardown_test_repo
}

# ---------- is_agent_context ----------

@test "is_agent_context: returns true when CLAUDE_SPAWNED_BY is set" {
  export CLAUDE_SPAWNED_BY="orchestrator-session-123"
  run is_agent_context
  [ "$status" -eq 0 ]
}

@test "is_agent_context: returns true when state file has isAgent true" {
  local sid="test-agent-state"
  init_state "$sid" "main" ""

  local state_file
  state_file=$(get_state_file "$sid")
  update_state "$state_file" '.isAgent = true'

  run is_agent_context "$sid"
  [ "$status" -eq 0 ]

  rm -f "$state_file"
}

@test "is_agent_context: returns false when neither env var nor state flag is set" {
  local sid="test-agent-none"
  init_state "$sid" "main" ""

  run is_agent_context "$sid"
  [ "$status" -eq 1 ]

  local state_file
  state_file=$(get_state_file "$sid")
  rm -f "$state_file"
}

@test "is_agent_context: returns false with no args and no env var" {
  run is_agent_context
  [ "$status" -eq 1 ]
}

@test "is_agent_context: env var takes precedence over state" {
  export CLAUDE_SPAWNED_BY="orchestrator"
  local sid="test-agent-both"
  init_state "$sid" "main" ""

  # State says not an agent, but env var overrides
  run is_agent_context "$sid"
  [ "$status" -eq 0 ]

  local state_file
  state_file=$(get_state_file "$sid")
  rm -f "$state_file"
}

# ---------- is_operation_agent_restricted ----------

@test "is_operation_agent_restricted: push is restricted by default config" {
  local config='{"agentTeams":{"suppressPromptsForAgents":true,"orchestratorOnly":["push","mr"]}}'
  run is_operation_agent_restricted "$config" "push"
  [ "$status" -eq 0 ]
}

@test "is_operation_agent_restricted: mr is restricted by default config" {
  local config='{"agentTeams":{"suppressPromptsForAgents":true,"orchestratorOnly":["push","mr"]}}'
  run is_operation_agent_restricted "$config" "mr"
  [ "$status" -eq 0 ]
}

@test "is_operation_agent_restricted: commit is not restricted by default" {
  local config='{"agentTeams":{"suppressPromptsForAgents":true,"orchestratorOnly":["push","mr"]}}'
  run is_operation_agent_restricted "$config" "commit"
  [ "$status" -eq 1 ]
}

@test "is_operation_agent_restricted: nothing restricted when suppressPromptsForAgents is false" {
  local config='{"agentTeams":{"suppressPromptsForAgents":false,"orchestratorOnly":["push","mr"]}}'
  run is_operation_agent_restricted "$config" "push"
  [ "$status" -eq 1 ]
}

@test "is_operation_agent_restricted: custom orchestratorOnly list respected" {
  local config='{"agentTeams":{"suppressPromptsForAgents":true,"orchestratorOnly":["push","mr","rebase","branch-freshness"]}}'
  run is_operation_agent_restricted "$config" "rebase"
  [ "$status" -eq 0 ]

  run is_operation_agent_restricted "$config" "branch-freshness"
  [ "$status" -eq 0 ]

  run is_operation_agent_restricted "$config" "commit"
  [ "$status" -eq 1 ]
}
