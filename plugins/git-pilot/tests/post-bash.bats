#!/usr/bin/env bats

# Tests for post-bash.sh: push prompt after commit, push rejection detection,
# agent suppression, error resilience, and anti-pattern compliance.

load test_helper/common

HOOK_SCRIPT="$PLUGIN_DIR/scripts/post-bash.sh"

setup() {
  setup_test_repo
  setup_remote_repo

  # Create a feature branch with an unpushed commit
  cd "$TEST_REPO"
  git checkout -b feat/test-feature >/dev/null 2>&1
  echo "feature" > feature.txt
  git add feature.txt
  git commit -m "feat: add feature" >/dev/null 2>&1

  unset CLAUDE_SPAWNED_BY
}

teardown() {
  unset CLAUDE_SPAWNED_BY
  rm -f /tmp/git-pilot-test-post-bash-*.json
  teardown_test_repo
}

# Helper: run the hook script with JSON input
run_hook() {
  local json="$1"
  run bash -c "echo '$json' | bash '$HOOK_SCRIPT'"
}

# ---------- Push prompt after git commit ----------

@test "post-bash: unpushed commits after git commit uses additionalContext" {
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-1","tool_input":{"command":"git commit -m \"feat: something\""}}'

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext' >/dev/null
  echo "$output" | jq -e '.continue == true' >/dev/null
}

@test "post-bash: unpushed commits message matches expected format" {
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-2","tool_input":{"command":"git commit -m \"feat: something\""}}'

  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext')
  [[ "$ctx" == *"[git-pilot]"* ]]
  [[ "$ctx" == *"unpushed commit(s) on 'feat/test-feature'"* ]]
}

@test "post-bash: unpushed commits output does not use systemMessage" {
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-3","tool_input":{"command":"git commit -m \"feat: something\""}}'

  [ "$status" -eq 0 ]
  local has_sys
  has_sys=$(echo "$output" | jq 'has("systemMessage")')
  [ "$has_sys" = "false" ]
}

@test "post-bash: output is valid JSON" {
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-4","tool_input":{"command":"git commit -m \"feat: something\""}}'

  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null
}

# ---------- Push rejection detection ----------

@test "post-bash: push rejection uses additionalContext" {
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-5","tool_input":{"command":"git push origin feat/test-feature"},"tool_result":{"exitCode":1,"stdout":"","stderr":"error: failed to push some refs, rejected, non-fast-forward"}}'

  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext')
  [[ "$ctx" == "[git-pilot] Push rejected"* ]]
}

@test "post-bash: push rejection message contains branch name" {
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-6","tool_input":{"command":"git push origin feat/test-feature"},"tool_result":{"exitCode":1,"stdout":"","stderr":"rejected non-fast-forward"}}'

  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext')
  [[ "$ctx" == *"feat/test-feature"* ]]
}

@test "post-bash: push rejection does not use systemMessage" {
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-7","tool_input":{"command":"git push origin feat/test-feature"},"tool_result":{"exitCode":1,"stdout":"","stderr":"rejected"}}'

  [ "$status" -eq 0 ]
  local has_sys
  has_sys=$(echo "$output" | jq 'has("systemMessage")')
  [ "$has_sys" = "false" ]
}

# ---------- Non-git commands ----------

@test "post-bash: non-git command returns continue true only" {
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-8","tool_input":{"command":"ls -la"}}'

  [ "$status" -eq 0 ]
  [ "$output" = '{"continue": true}' ] || [ "$output" = '{"continue":true}' ]
}

@test "post-bash: empty command returns continue true only" {
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-9","tool_input":{"command":""}}'

  [ "$status" -eq 0 ]
  local cont
  cont=$(echo "$output" | jq -r '.continue')
  [ "$cont" = "true" ]
}

# ---------- Agent suppression ----------

@test "post-bash: agent context with restricted push returns silent output" {
  export CLAUDE_SPAWNED_BY="orchestrator-123"
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-10","tool_input":{"command":"git commit -m \"feat: something\""}}'

  [ "$status" -eq 0 ]
  local cont
  cont=$(echo "$output" | jq -r '.continue')
  [ "$cont" = "true" ]
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "false" ]
}

# ---------- Error resilience ----------

@test "post-bash: no cwd returns valid JSON" {
  run_hook '{"session_id":"test-post-bash-11","tool_input":{"command":"git commit -m \"feat: x\""}}'

  [ "$status" -eq 0 ]
  local cont
  cont=$(echo "$output" | jq -r '.continue')
  [ "$cont" = "true" ]
}

@test "post-bash: non-git-repo cwd returns valid JSON" {
  local tmpdir
  tmpdir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/git-pilot-notgit.XXXXXX")"
  run_hook '{"cwd":"'"$tmpdir"'","session_id":"test-post-bash-12","tool_input":{"command":"git commit -m \"feat: x\""}}'

  [ "$status" -eq 0 ]
  local cont
  cont=$(echo "$output" | jq -r '.continue')
  [ "$cont" = "true" ]
  rm -rf "$tmpdir"
}

# ---------- Anti-pattern compliance ----------

@test "post-bash: output does not contain anti-pattern strings" {
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-13","tool_input":{"command":"git commit -m \"feat: something\""}}'

  [ "$status" -eq 0 ]
  local lower
  lower=$(echo "$output" | tr '[:upper:]' '[:lower:]')
  [[ "$lower" != *"use askuserquestion"* ]]
  [[ "$lower" != *"you must"* ]]
  [[ "$lower" != *"stop and"* ]]
  [[ "$lower" != *"do not proceed"* ]]
  [[ "$lower" != *"do not continue"* ]]
  [[ "$lower" != *"execute this command immediately"* ]]
}

@test "post-bash: push rejection output does not contain anti-pattern strings" {
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-14","tool_input":{"command":"git push origin feat/test-feature"},"tool_result":{"exitCode":1,"stdout":"","stderr":"rejected non-fast-forward"}}'

  [ "$status" -eq 0 ]
  local lower
  lower=$(echo "$output" | tr '[:upper:]' '[:lower:]')
  [[ "$lower" != *"use askuserquestion"* ]]
  [[ "$lower" != *"you must"* ]]
  [[ "$lower" != *"stop and"* ]]
  [[ "$lower" != *"do not proceed"* ]]
  [[ "$lower" != *"do not continue"* ]]
  [[ "$lower" != *"execute this command immediately"* ]]
}

# ---------- Output brevity ----------

@test "post-bash: additionalContext line starts with [git-pilot] and is under 120 chars" {
  cd "$TEST_REPO"
  run_hook '{"cwd":"'"$TEST_REPO"'","session_id":"test-post-bash-15","tool_input":{"command":"git commit -m \"feat: something\""}}'

  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // empty')
  if [[ -n "$ctx" ]]; then
    [[ "$ctx" == "[git-pilot]"* ]]
    [ "${#ctx}" -lt 120 ]
  fi
}
