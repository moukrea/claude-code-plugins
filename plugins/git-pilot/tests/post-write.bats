#!/usr/bin/env bats

# Tests for post-write.sh: suggest mode, auto mode, silent mode,
# agent suppression, state tracking, error resilience, and anti-pattern compliance.

load test_helper/common

HOOK_SCRIPT="$PLUGIN_DIR/scripts/post-write.sh"

setup() {
  setup_test_repo

  cd "$TEST_REPO"
  git checkout -b feat/test-feature >/dev/null 2>&1

  # Create a default local config with autoCommit enabled
  mkdir -p "$TEST_REPO/.claude"
  echo '{"autoCommit":{"enabled":true,"mode":"suggest","threshold":3}}' > "$TEST_REPO/.claude/git-pilot.json"

  TEST_SESSION="test-post-write-$$-$RANDOM"

  unset CLAUDE_SPAWNED_BY
}

teardown() {
  unset CLAUDE_SPAWNED_BY
  rm -f "/tmp/git-pilot-${TEST_SESSION}.json"
  teardown_test_repo
}

# Helper: run the hook script with JSON input
run_hook() {
  local json="$1"
  run bash -c "echo '$json' | bash '$HOOK_SCRIPT'"
}

# Helper: run the hook N times to reach threshold
run_hook_n_times() {
  local n="$1"
  local session="$2"
  local file_prefix="${3:-src/file}"
  for i in $(seq 1 "$n"); do
    local json='{"cwd":"'"$TEST_REPO"'","session_id":"'"$session"'","tool_input":{"file_path":"'"${file_prefix}${i}.py"'"}}'
    echo "$json" | bash "$HOOK_SCRIPT"
  done
}

# ---------- Suggest mode ----------

@test "post-write: suggest mode uses additionalContext at threshold" {
  cd "$TEST_REPO"
  # Run below threshold (2 of 3)
  run_hook_n_times 2 "$TEST_SESSION" "src/a" >/dev/null 2>&1

  # Third call should trigger
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$TEST_SESSION"'","tool_input":{"file_path":"src/a3.py"}}'

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext' >/dev/null
  echo "$output" | jq -e '.continue == true' >/dev/null
}

@test "post-write: suggest mode message matches expected format" {
  cd "$TEST_REPO"
  run_hook_n_times 2 "$TEST_SESSION" "src/b" >/dev/null 2>&1

  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$TEST_SESSION"'","tool_input":{"file_path":"src/b3.py"}}'

  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext')
  [[ "$ctx" == "[git-pilot] 3 file changes since last commit"* ]]
}

@test "post-write: suggest mode does not use systemMessage" {
  cd "$TEST_REPO"
  run_hook_n_times 2 "$TEST_SESSION" "src/c" >/dev/null 2>&1

  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$TEST_SESSION"'","tool_input":{"file_path":"src/c3.py"}}'

  [ "$status" -eq 0 ]
  local has_sys
  has_sys=$(echo "$output" | jq 'has("systemMessage")')
  [ "$has_sys" = "false" ]
}

# ---------- Auto mode ----------

@test "post-write: auto mode uses additionalContext at threshold" {
  cd "$TEST_REPO"
  echo '{"autoCommit":{"enabled":true,"mode":"auto","threshold":2}}' > "$TEST_REPO/.claude/git-pilot.json"

  local session="test-pw-auto-$$-$RANDOM"
  run_hook_n_times 1 "$session" "src/d" >/dev/null 2>&1

  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$session"'","tool_input":{"file_path":"src/d2.py"}}'

  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext')
  [[ "$ctx" == "[git-pilot] Auto-commit threshold reached"* ]]

  rm -f "/tmp/git-pilot-${session}.json"
}

@test "post-write: auto mode does not use systemMessage" {
  cd "$TEST_REPO"
  echo '{"autoCommit":{"enabled":true,"mode":"auto","threshold":2}}' > "$TEST_REPO/.claude/git-pilot.json"

  local session="test-pw-auto2-$$-$RANDOM"
  run_hook_n_times 1 "$session" "src/e" >/dev/null 2>&1

  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$session"'","tool_input":{"file_path":"src/e2.py"}}'

  [ "$status" -eq 0 ]
  local has_sys
  has_sys=$(echo "$output" | jq 'has("systemMessage")')
  [ "$has_sys" = "false" ]

  rm -f "/tmp/git-pilot-${session}.json"
}

# ---------- Silent mode ----------

@test "post-write: silent mode performs git commit and reports result" {
  cd "$TEST_REPO"
  echo '{"autoCommit":{"enabled":true,"mode":"silent","threshold":2,"wipPrefix":"wip: "}}' > "$TEST_REPO/.claude/git-pilot.json"

  # Create actual files so git commit works
  echo "content1" > "$TEST_REPO/silent1.txt"
  git add "$TEST_REPO/silent1.txt" >/dev/null 2>&1

  local session="test-pw-silent-$$-$RANDOM"
  run_hook_n_times 1 "$session" "src/f" >/dev/null 2>&1

  echo "content2" > "$TEST_REPO/silent2.txt"
  git add "$TEST_REPO/silent2.txt" >/dev/null 2>&1

  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$session"'","tool_input":{"file_path":"src/f2.py"}}'

  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext')
  [[ "$ctx" == "[git-pilot] Auto-committed:"* ]] || [[ "$ctx" == "[git-pilot] Auto-commit failed:"* ]]

  rm -f "/tmp/git-pilot-${session}.json"
}

# ---------- Below threshold ----------

@test "post-write: below threshold produces no additionalContext" {
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$TEST_SESSION"'","tool_input":{"file_path":"src/single.py"}}'

  [ "$status" -eq 0 ]
  # Below threshold: no output or just exit 0
  if [[ -n "$output" ]]; then
    local has_ctx
    has_ctx=$(echo "$output" | jq 'has("additionalContext")' 2>/dev/null || echo "false")
    [ "$has_ctx" = "false" ]
  fi
}

# ---------- State tracking ----------

@test "post-write: changeCount resets after threshold" {
  cd "$TEST_REPO"
  source_script "state.sh"

  local session="test-pw-reset-$$-$RANDOM"

  # Reach threshold (3 calls)
  run_hook_n_times 3 "$session" "src/g" >/dev/null 2>&1

  # After threshold, changeCount should be reset to 0
  local state_file="/tmp/git-pilot-${session}.json"
  local count
  count=$(cat "$state_file" | jq '.changeCount')
  [ "$count" = "0" ]

  rm -f "$state_file"
}

# ---------- Agent suppression ----------

@test "post-write: agent context produces no output" {
  export CLAUDE_SPAWNED_BY="orchestrator-456"
  cd "$TEST_REPO"

  local session="test-pw-agent-$$-$RANDOM"
  run_hook_n_times 2 "$session" "src/h" >/dev/null 2>&1

  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$session"'","tool_input":{"file_path":"src/h3.py"}}'

  [ "$status" -eq 0 ]
  # Agent context should exit silently (no output or empty)
  if [[ -n "$output" ]]; then
    local has_ctx
    has_ctx=$(echo "$output" | jq 'has("additionalContext")' 2>/dev/null || echo "false")
    [ "$has_ctx" = "false" ]
  fi

  rm -f "/tmp/git-pilot-${session}.json"
}

# ---------- Auto-commit disabled ----------

@test "post-write: disabled auto-commit produces no output" {
  cd "$TEST_REPO"
  echo '{"autoCommit":{"enabled":false}}' > "$TEST_REPO/.claude/git-pilot.json"

  local session="test-pw-disabled-$$-$RANDOM"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$session"'","tool_input":{"file_path":"src/disabled.py"}}'

  [ "$status" -eq 0 ]
  # Disabled: no output or empty
  if [[ -n "$output" ]]; then
    local has_ctx
    has_ctx=$(echo "$output" | jq 'has("additionalContext")' 2>/dev/null || echo "false")
    [ "$has_ctx" = "false" ]
  fi

  rm -f "/tmp/git-pilot-${session}.json"
}

# ---------- Output format validation ----------

@test "post-write: output is valid JSON when threshold reached" {
  cd "$TEST_REPO"
  run_hook_n_times 2 "$TEST_SESSION" "src/j" >/dev/null 2>&1

  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$TEST_SESSION"'","tool_input":{"file_path":"src/j3.py"}}'

  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null
}

# ---------- Anti-pattern compliance ----------

@test "post-write: suggest mode output does not contain anti-pattern strings" {
  cd "$TEST_REPO"

  local session="test-pw-anti-$$-$RANDOM"
  run_hook_n_times 2 "$session" "src/k" >/dev/null 2>&1

  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$session"'","tool_input":{"file_path":"src/k3.py"}}'

  [ "$status" -eq 0 ]
  local lower
  lower=$(echo "$output" | tr '[:upper:]' '[:lower:]')
  [[ "$lower" != *"use askuserquestion"* ]]
  [[ "$lower" != *"you must"* ]]
  [[ "$lower" != *"stop and"* ]]
  [[ "$lower" != *"do not proceed"* ]]
  [[ "$lower" != *"do not continue"* ]]
  [[ "$lower" != *"execute this command immediately"* ]]

  rm -f "/tmp/git-pilot-${session}.json"
}

@test "post-write: auto mode output does not contain anti-pattern strings" {
  cd "$TEST_REPO"
  echo '{"autoCommit":{"enabled":true,"mode":"auto","threshold":2}}' > "$TEST_REPO/.claude/git-pilot.json"

  local session="test-pw-anti2-$$-$RANDOM"
  run_hook_n_times 1 "$session" "src/l" >/dev/null 2>&1

  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$session"'","tool_input":{"file_path":"src/l2.py"}}'

  [ "$status" -eq 0 ]
  local lower
  lower=$(echo "$output" | tr '[:upper:]' '[:lower:]')
  [[ "$lower" != *"use askuserquestion"* ]]
  [[ "$lower" != *"you must"* ]]
  [[ "$lower" != *"stop and"* ]]
  [[ "$lower" != *"do not proceed"* ]]
  [[ "$lower" != *"do not continue"* ]]
  [[ "$lower" != *"execute this command immediately"* ]]

  rm -f "/tmp/git-pilot-${session}.json"
}

# ---------- Output brevity ----------

@test "post-write: additionalContext line starts with [git-pilot] and is under 120 chars" {
  cd "$TEST_REPO"

  local session="test-pw-brevity-$$-$RANDOM"
  run_hook_n_times 2 "$session" "src/m" >/dev/null 2>&1

  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"'"$session"'","tool_input":{"file_path":"src/m3.py"}}'

  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // empty')
  if [[ -n "$ctx" ]]; then
    [[ "$ctx" == "[git-pilot]"* ]]
    [ "${#ctx}" -lt 120 ]
  fi

  rm -f "/tmp/git-pilot-${session}.json"
}
