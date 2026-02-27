#!/usr/bin/env bats

# Tests for session-start.sh hook output format, condition-to-output mapping,
# anti-pattern enforcement, and error resilience.

load test_helper/common

HOOK_SCRIPT="$PLUGIN_DIR/scripts/session-start.sh"

setup() {
  setup_test_repo
  # Override HOME to prevent global config from interfering
  export ORIGINAL_HOME="$HOME"
  export HOME="$TEST_REPO"
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  rm -f /tmp/git-pilot-test-session-start-*.json
  teardown_test_repo
}

# Helper: run the session-start hook with the given cwd and session_id.
# Wraps in a subshell to redirect stderr away from bats' $output capture.
run_hook() {
  local cwd="${1:-$TEST_REPO}"
  local session_id="${2:-test-session-start-$$}"
  run bash -c 'bash "$1" 2>/dev/null <<< "$2"' _ \
    "$HOOK_SCRIPT" "{\"cwd\": \"${cwd}\", \"session_id\": \"${session_id}\"}"
}

# Helper: push a commit to TEST_REMOTE from a temporary clone.
# Sets CLONE_DIR for cleanup. The clone checks out 'main' explicitly.
push_remote_commit() {
  local msg="${1:-feat: remote change}"
  local filename="${2:-remote-file.txt}"
  CLONE_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/git-pilot-clone.XXXXXX")"
  git clone "$TEST_REMOTE" "$CLONE_DIR" 2>/dev/null
  cd "$CLONE_DIR"
  # Ensure we're on main (bare repos may default to a different branch)
  git checkout main 2>/dev/null || git checkout -b main origin/main 2>/dev/null
  git config user.name "Other"
  git config user.email "other@example.com"
  echo "$msg" > "$filename"
  git add "$filename"
  git -c commit.gpgsign=false commit -m "$msg" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
  cd "$TEST_REPO"
}

# ---------- Output Format ----------

@test "output is valid JSON" {
  run_hook
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

@test "output contains continue: true" {
  run_hook
  [ "$status" -eq 0 ]
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
}

@test "output uses additionalContext not systemMessage" {
  run_hook
  [ "$status" -eq 0 ]
  # systemMessage must NOT be present
  local sys_msg
  sys_msg=$(echo "$output" | jq 'has("systemMessage")')
  [ "$sys_msg" = "false" ]
}

@test "additionalContext is present when there is context to report" {
  # On default branch with autoCreate enabled triggers "[git-pilot] On default branch"
  run_hook
  [ "$status" -eq 0 ]
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "true" ]
}

# ---------- Anti-Pattern Strings ----------

@test "output contains no anti-pattern strings" {
  run_hook
  [ "$status" -eq 0 ]

  # Case-insensitive checks for forbidden phrases
  [[ ! "${output,,}" == *"use askuserquestion"* ]]
  [[ ! "${output,,}" == *"you must"* ]]
  [[ ! "${output,,}" == *"stop and"* ]]
  [[ ! "${output,,}" == *"do not proceed"* ]]
  [[ ! "${output,,}" == *"do not continue"* ]]
  [[ ! "${output,,}" == *"execute this command immediately"* ]]
}

@test "on default branch output contains no anti-pattern strings" {
  # This is the scenario that used to be most verbose in v2
  run_hook
  [ "$status" -eq 0 ]

  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ ! "${ctx,,}" == *"use askuserquestion"* ]]
  [[ ! "${ctx,,}" == *"you must"* ]]
  [[ ! "${ctx,,}" == *"stop and"* ]]
  [[ ! "${ctx,,}" == *"do not proceed"* ]]
  [[ ! "${ctx,,}" == *"do not continue"* ]]
  [[ ! "${ctx,,}" == *"execute this command immediately"* ]]
}

# ---------- Output Brevity Rules ----------

@test "each additionalContext line starts with [git-pilot]" {
  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  if [[ -n "$ctx" ]]; then
    while IFS= read -r line; do
      [[ "$line" == "[git-pilot]"* ]]
    done <<< "$ctx"
  fi
}

@test "each additionalContext line is under 120 characters" {
  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  if [[ -n "$ctx" ]]; then
    while IFS= read -r line; do
      [ "${#line}" -lt 120 ]
    done <<< "$ctx"
  fi
}

# ---------- Condition: On Default Branch ----------

@test "on default branch: outputs correct message" {
  # TEST_REPO starts on 'main' which is the default branch
  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] On default branch 'main'"* ]]
}

# ---------- Condition: No Remote Configured ----------

@test "no remote configured: outputs correct message" {
  # TEST_REPO has no remote by default
  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] No git remote configured"* ]]
}

# ---------- Condition: Detached HEAD ----------

@test "detached HEAD: outputs correct message with sha" {
  local head_sha
  head_sha=$(cd "$TEST_REPO" && git rev-parse --short HEAD)
  cd "$TEST_REPO"
  git checkout "$head_sha" >/dev/null 2>&1

  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] Detached HEAD at ${head_sha}"* ]]
}

@test "detached HEAD: includes previous branch when available" {
  cd "$TEST_REPO"
  # Create and checkout a branch, then detach
  git checkout -b feat/test-feature >/dev/null 2>&1
  echo "feature work" > feature.txt
  git add feature.txt
  git commit -m "feat: add feature" >/dev/null 2>&1
  local head_sha
  head_sha=$(git rev-parse --short HEAD)
  git checkout "$head_sha" >/dev/null 2>&1

  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] Detached HEAD at ${head_sha} (previous branch: feat/test-feature)"* ]]
}

# ---------- Condition: Branch Behind Remote ----------

@test "branch behind remote: outputs correct message" {
  setup_remote_repo
  push_remote_commit "feat: remote change" "remote-file.txt"

  cd "$TEST_REPO"
  git fetch origin >/dev/null 2>&1

  # The hook will attempt fast-forward; if it succeeds we get ff message, else behind
  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] Branch 'main' fast-forwarded 1 commit(s)"* ]] || \
  [[ "$ctx" == *"[git-pilot] Branch 'main' is 1 commit(s) behind remote"* ]]

  rm -rf "$CLONE_DIR"
}

# ---------- Condition: Branch Ahead (Unpushed) ----------

@test "branch ahead: outputs unpushed commits message" {
  setup_remote_repo

  cd "$TEST_REPO"
  echo "local change" > local-file.txt
  git add local-file.txt
  git commit -m "feat: local change" >/dev/null 2>&1

  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] 1 unpushed commit(s) on 'main'"* ]]
}

# ---------- Condition: Branch Diverged ----------

@test "branch diverged: outputs diverged message" {
  setup_remote_repo
  push_remote_commit "feat: remote diverge" "diverge-remote.txt"

  # Make a local commit in test repo
  cd "$TEST_REPO"
  git fetch origin >/dev/null 2>&1
  echo "local diverge" > diverge-local.txt
  git add diverge-local.txt
  git -c commit.gpgsign=false commit -m "feat: local diverge" >/dev/null 2>&1

  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] Branch 'main' diverged: 1 local, 1 remote"* ]]

  rm -rf "$CLONE_DIR"
}

# ---------- Condition: Fast-Forward Success ----------

@test "fast-forward success: outputs correct message" {
  setup_remote_repo
  push_remote_commit "feat: remote ff change" "ff-file.txt"

  cd "$TEST_REPO"
  git fetch origin >/dev/null 2>&1

  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] Branch 'main' fast-forwarded 1 commit(s)"* ]]

  rm -rf "$CLONE_DIR"
}

# ---------- Condition: Fetch Failed ----------

@test "fetch failed: outputs correct message" {
  # Add a bogus remote
  cd "$TEST_REPO"
  git remote add origin "file:///nonexistent/path/to/repo"

  # Create a config with zero retries and zero delay for speed
  mkdir -p "$TEST_REPO/.claude"
  echo '{"git":{"autoFetch":true,"fetchRetries":0,"fetchRetryDelaySec":0}}' > "$TEST_REPO/.claude/git-pilot.json"

  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] Remote fetch failed -- proceeding offline"* ]]
}

# ---------- Condition: Git Repo Auto-Initialized ----------

@test "git repo auto-initialized: outputs correct message" {
  # Create a non-git directory
  local non_git_dir
  non_git_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/git-pilot-nongit.XXXXXX")"

  run_hook "$non_git_dir"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] Initialized git repo (branch: main)"* ]]

  rm -rf "$non_git_dir"
}

# ---------- Error Resilience ----------

@test "empty cwd defaults gracefully" {
  # Pass cwd as "." which defaults to current dir
  cd "$TEST_REPO"
  run bash -c 'bash "$1" 2>/dev/null <<< "$2"' _ \
    "$HOOK_SCRIPT" '{"cwd": ".", "session_id": "test-empty-cwd"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

@test "missing session_id still produces valid JSON" {
  run bash -c 'bash "$1" 2>/dev/null <<< "$2"' _ \
    "$HOOK_SCRIPT" "{\"cwd\": \"${TEST_REPO}\"}"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
}

@test "empty session_id still produces valid JSON" {
  run bash -c 'bash "$1" 2>/dev/null <<< "$2"' _ \
    "$HOOK_SCRIPT" "{\"cwd\": \"${TEST_REPO}\", \"session_id\": \"\"}"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
}

# ---------- Session State Initialization ----------

@test "session state file is created with correct session_id" {
  local sid="test-session-start-state-$$"
  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]

  local state_file="/tmp/git-pilot-${sid}.json"
  [ -f "$state_file" ]

  local stored_sid
  stored_sid=$(jq -r '.sessionId' "$state_file")
  [ "$stored_sid" = "$sid" ]

  rm -f "$state_file"
}

@test "session state records headAtStart" {
  local sid="test-session-start-head-$$"
  local expected_head
  expected_head=$(cd "$TEST_REPO" && git rev-parse HEAD)

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]

  local state_file="/tmp/git-pilot-${sid}.json"
  local head_at_start
  head_at_start=$(jq -r '.headAtStart' "$state_file")
  [ "$head_at_start" = "$expected_head" ]

  rm -f "$state_file"
}

# ---------- No Messages: Minimal Output ----------

@test "up-to-date branch with remote produces no behind/ahead message" {
  setup_remote_repo

  run_hook
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  # Should not contain behind or diverged messages
  [[ ! "$ctx" == *"commit(s) behind remote"* ]]
  [[ ! "$ctx" == *"diverged"* ]]
  [[ ! "$ctx" == *"unpushed"* ]]
}
