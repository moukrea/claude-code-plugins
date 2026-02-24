#!/usr/bin/env bats

# Tests for config.sh: load_config, get_config, normalize_protect_default_branch.

load test_helper/common

setup() {
  setup_test_repo
  source_script "config.sh"
}

teardown() {
  teardown_test_repo
}

# ---------- normalize_protect_default_branch ----------

@test "normalize_protect_default_branch: true normalizes to warn" {
  run normalize_protect_default_branch "true"
  [ "$status" -eq 0 ]
  [ "$output" = "warn" ]
}

@test "normalize_protect_default_branch: false normalizes to off" {
  run normalize_protect_default_branch "false"
  [ "$status" -eq 0 ]
  [ "$output" = "off" ]
}

@test "normalize_protect_default_branch: warn passes through" {
  run normalize_protect_default_branch "warn"
  [ "$status" -eq 0 ]
  [ "$output" = "warn" ]
}

@test "normalize_protect_default_branch: block passes through" {
  run normalize_protect_default_branch "block"
  [ "$status" -eq 0 ]
  [ "$output" = "block" ]
}

@test "normalize_protect_default_branch: off passes through" {
  run normalize_protect_default_branch "off"
  [ "$status" -eq 0 ]
  [ "$output" = "off" ]
}

@test "normalize_protect_default_branch: unknown value defaults to warn" {
  run normalize_protect_default_branch "garbage"
  [ "$status" -eq 0 ]
  [ "$output" = "warn" ]
}

# ---------- get_config ----------

@test "get_config: returns value for existing key" {
  local config='{"git":{"defaultBranch":"develop"}}'
  run get_config "$config" '.git.defaultBranch' 'main'
  [ "$status" -eq 0 ]
  [ "$output" = "develop" ]
}

@test "get_config: returns default for missing key" {
  local config='{"git":{}}'
  run get_config "$config" '.git.fetchRetries' '2'
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "get_config: returns default for null value" {
  local config='{"git":{"fetchRetries":null}}'
  run get_config "$config" '.git.fetchRetries' '5'
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

# ---------- load_config ----------

@test "load_config: loads defaults when no overrides exist" {
  run load_config "$TEST_REPO"
  [ "$status" -eq 0 ]
  # Should include the default branch setting from defaults/config.json
  local default_branch
  default_branch=$(echo "$output" | jq -r '.git.defaultBranch')
  [ "$default_branch" = "main" ]
}

@test "load_config: local config overrides defaults" {
  create_config "$TEST_REPO/.claude/git-pilot.json" '{"git":{"defaultBranch":"develop"}}'

  run load_config "$TEST_REPO"
  [ "$status" -eq 0 ]
  local default_branch
  default_branch=$(echo "$output" | jq -r '.git.defaultBranch')
  [ "$default_branch" = "develop" ]
}

@test "load_config: v2 config with all new keys works" {
  local v2='{"git":{"defaultBranch":"main","protectDefaultBranch":"block","fetchRetries":3},"rebase":{"conflictStrategy":"abort"},"worktree":{"enabled":true},"agentTeams":{"suppressPromptsForAgents":true}}'
  create_config "$TEST_REPO/.claude/git-pilot.json" "$v2"

  run load_config "$TEST_REPO"
  [ "$status" -eq 0 ]
  local protect
  protect=$(echo "$output" | jq -r '.git.protectDefaultBranch')
  [ "$protect" = "block" ]
  local retries
  retries=$(echo "$output" | jq -r '.git.fetchRetries')
  [ "$retries" = "3" ]
}

@test "load_config: missing new keys fall back to defaults" {
  # Minimal config with no rebase/worktree/agentTeams keys
  create_config "$TEST_REPO/.claude/git-pilot.json" '{"git":{"defaultBranch":"main"}}'

  run load_config "$TEST_REPO"
  [ "$status" -eq 0 ]
  # The rebase key should come from defaults
  local conflict_strategy
  conflict_strategy=$(echo "$output" | jq -r '.rebase.conflictStrategy')
  [ "$conflict_strategy" = "prompt" ]
}
