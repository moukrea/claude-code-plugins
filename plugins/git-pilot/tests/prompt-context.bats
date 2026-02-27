#!/usr/bin/env bats

# Tests for prompt-context.sh hook output format, skip conditions,
# anti-pattern enforcement, and output brevity rules.

load test_helper/common

HOOK_SCRIPT="$PLUGIN_DIR/scripts/prompt-context.sh"

setup() {
  setup_test_repo
  export ORIGINAL_HOME="$HOME"
  export HOME="$TEST_REPO"
  unset CLAUDE_SPAWNED_BY
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  unset CLAUDE_SPAWNED_BY
  teardown_test_repo
}

# Helper: run the prompt-context hook with the given cwd and session_id.
run_hook() {
  local cwd="${1:-$TEST_REPO}"
  local session_id="${2:-test-prompt-ctx-$$}"
  run bash "$HOOK_SCRIPT" <<< "{\"cwd\": \"${cwd}\", \"session_id\": \"${session_id}\"}"
}

# Helper: create a feature branch with commits ahead of default.
setup_feature_branch() {
  local branch_name="${1:-feat/test-feature}"
  local commit_count="${2:-3}"
  cd "$TEST_REPO"
  git checkout -b "$branch_name" >/dev/null 2>&1
  for i in $(seq 1 "$commit_count"); do
    echo "change $i" > "file-${i}.txt"
    git add "file-${i}.txt"
    git commit -m "feat: change $i" >/dev/null 2>&1
  done
}

# ---------- Output Format ----------

@test "output is valid JSON" {
  setup_feature_branch
  run_hook
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

@test "output contains continue: true" {
  setup_feature_branch
  run_hook
  [ "$status" -eq 0 ]
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
}

@test "output uses additionalContext not systemMessage" {
  setup_feature_branch
  run_hook
  [ "$status" -eq 0 ]
  # additionalContext must be present
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "true" ]
  # systemMessage must NOT be present
  local sys_msg
  sys_msg=$(echo "$output" | jq 'has("systemMessage")')
  [ "$sys_msg" = "false" ]
}

# ---------- Exact Output Format ----------

@test "output matches exact format: Branch '{branch}' ({purpose}, {n} commits)" {
  setup_feature_branch "feat/cd-pipeline" 5
  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext')
  [ "$ctx" = "[git-pilot] Branch 'feat/cd-pipeline' (cd pipeline, 5 commits)" ]
}

@test "output format with single commit" {
  setup_feature_branch "fix/login-bug" 1
  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext')
  [ "$ctx" = "[git-pilot] Branch 'fix/login-bug' (login bug, 1 commits)" ]
}

# ---------- Anti-Pattern Strings ----------

@test "output contains no anti-pattern strings" {
  setup_feature_branch
  run_hook
  [ "$status" -eq 0 ]

  [[ ! "${output,,}" == *"use askuserquestion"* ]]
  [[ ! "${output,,}" == *"you must"* ]]
  [[ ! "${output,,}" == *"stop and"* ]]
  [[ ! "${output,,}" == *"do not proceed"* ]]
  [[ ! "${output,,}" == *"do not continue"* ]]
  [[ ! "${output,,}" == *"execute this command immediately"* ]]
}

@test "output contains no prompt-context-specific anti-patterns" {
  setup_feature_branch
  run_hook
  [ "$status" -eq 0 ]

  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ ! "${ctx,,}" == *"assess whether"* ]]
  [[ ! "${ctx,,}" == *"before acting"* ]]
  [[ ! "${ctx,,}" == *"recent commits"* ]]
}

@test "output does not list commit hashes" {
  setup_feature_branch "feat/test-feature" 5
  run_hook
  [ "$status" -eq 0 ]

  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  # Commit hashes are 7+ hex chars; output should not contain any
  # Use grep -E to check for 7+ consecutive hex characters (typical short hash)
  ! echo "$ctx" | grep -qE '[0-9a-f]{7,}'
}

# ---------- Output Brevity Rules ----------

@test "additionalContext line starts with [git-pilot]" {
  setup_feature_branch
  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == "[git-pilot]"* ]]
}

@test "additionalContext is a single line" {
  setup_feature_branch
  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  local line_count
  line_count=$(echo "$ctx" | wc -l | tr -d ' ')
  [ "$line_count" -eq 1 ]
}

@test "additionalContext line is under 120 characters" {
  setup_feature_branch
  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [ "${#ctx}" -lt 120 ]
}

# ---------- Skip Conditions ----------

@test "skip: on default branch produces continue true with no context" {
  # TEST_REPO starts on 'main' which is the default branch
  run_hook
  [ "$status" -eq 0 ]
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "false" ]
}

@test "skip: detached HEAD produces continue true with no context" {
  cd "$TEST_REPO"
  local head_sha
  head_sha=$(git rev-parse HEAD)
  git checkout "$head_sha" >/dev/null 2>&1

  run_hook
  [ "$status" -eq 0 ]
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "false" ]
}

@test "skip: branch with no commits produces continue true with no context" {
  cd "$TEST_REPO"
  # Create a branch but make no new commits
  git checkout -b feat/empty-branch >/dev/null 2>&1

  run_hook
  [ "$status" -eq 0 ]
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "false" ]
}

@test "skip: detection disabled produces continue true with no context" {
  setup_feature_branch
  # Disable unrelated work detection via local config
  mkdir -p "$TEST_REPO/.claude"
  echo '{"branch":{"unrelatedWorkDetection":false}}' > "$TEST_REPO/.claude/git-pilot.json"

  run_hook
  [ "$status" -eq 0 ]
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "false" ]
}

@test "skip: agent context produces continue true with no context" {
  setup_feature_branch
  export CLAUDE_SPAWNED_BY="orchestrator-session-123"

  run_hook
  [ "$status" -eq 0 ]
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "false" ]
}

@test "skip: no cwd produces continue true with no context" {
  run bash "$HOOK_SCRIPT" <<< '{"session_id": "test-no-cwd"}'
  [ "$status" -eq 0 ]
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "false" ]
}

@test "skip: not a git repo produces continue true with no context" {
  local non_git_dir
  non_git_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/git-pilot-nongit.XXXXXX")"

  run_hook "$non_git_dir"
  [ "$status" -eq 0 ]
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "false" ]

  rm -rf "$non_git_dir"
}

# ---------- Error Resilience ----------

@test "empty cwd produces valid JSON with continue true" {
  run bash "$HOOK_SCRIPT" <<< '{"cwd": "", "session_id": "test-empty-cwd"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
}

@test "missing session_id still produces valid JSON" {
  setup_feature_branch
  run bash "$HOOK_SCRIPT" <<< "{\"cwd\": \"${TEST_REPO}\"}"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}
