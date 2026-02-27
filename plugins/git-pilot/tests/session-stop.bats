#!/usr/bin/env bats

# Tests for session-stop.sh hook output format, condition-to-output mapping,
# anti-pattern enforcement, agent suppression, and error resilience.

load test_helper/common

HOOK_SCRIPT="$PLUGIN_DIR/scripts/session-stop.sh"

setup() {
  setup_test_repo
  # Override HOME to prevent global config from interfering
  export ORIGINAL_HOME="$HOME"
  export HOME="$TEST_REPO"
  # Ensure no agent context
  unset CLAUDE_SPAWNED_BY
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  rm -f /tmp/git-pilot-test-session-stop-*.json
  teardown_test_repo
}

# Helper: run the session-stop hook with the given cwd and session_id.
# Wraps in a subshell to redirect stderr away from bats' $output capture.
run_hook() {
  local cwd="${1:-$TEST_REPO}"
  local session_id="${2:-test-session-stop-$$}"
  run bash -c 'bash "$1" 2>/dev/null <<< "$2"' _ \
    "$HOOK_SCRIPT" "{\"cwd\": \"${cwd}\", \"session_id\": \"${session_id}\"}"
}

# Helper: initialize a session state file with headAtStart set to the given sha.
create_state() {
  local session_id="$1"
  local head_at_start="${2:-$(cd "$TEST_REPO" && git rev-parse HEAD)}"
  local state_file="/tmp/git-pilot-${session_id}.json"
  jq -n \
    --arg sid "$session_id" \
    --arg head "$head_at_start" \
    '{sessionId: $sid, headAtStart: $head, changeCount: 0, isAgent: false}' \
    > "$state_file"
}

# Helper: create a session state with isAgent: true for agent suppression tests.
create_agent_state() {
  local session_id="$1"
  local head_at_start="${2:-$(cd "$TEST_REPO" && git rev-parse HEAD)}"
  local state_file="/tmp/git-pilot-${session_id}.json"
  jq -n \
    --arg sid "$session_id" \
    --arg head "$head_at_start" \
    '{sessionId: $sid, headAtStart: $head, changeCount: 0, isAgent: true}' \
    > "$state_file"
}

# Helper: make a commit in TEST_REPO to simulate session work.
make_commit() {
  local msg="${1:-feat: test change}"
  local filename="${2:-test-file-$RANDOM.txt}"
  cd "$TEST_REPO"
  echo "$msg" > "$filename"
  git add "$filename"
  git -c commit.gpgsign=false commit -m "$msg" >/dev/null 2>&1
}

# Helper: push a commit to TEST_REMOTE from a temporary clone.
push_remote_commit() {
  local msg="${1:-feat: remote change}"
  local filename="${2:-remote-file.txt}"
  CLONE_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/git-pilot-clone.XXXXXX")"
  git clone "$TEST_REMOTE" "$CLONE_DIR" 2>/dev/null
  cd "$CLONE_DIR"
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

@test "no changes: output is valid JSON with continue true" {
  local sid="test-session-stop-fmt-$$"
  create_state "$sid"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
}

@test "with changes: output uses additionalContext not systemMessage" {
  local sid="test-session-stop-ctx-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  # Create a feature branch and make a commit
  cd "$TEST_REPO"
  git checkout -b feat/test-ctx >/dev/null 2>&1
  make_commit "feat: context test"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty

  # systemMessage must NOT be present
  local sys_msg
  sys_msg=$(echo "$output" | jq 'has("systemMessage")')
  [ "$sys_msg" = "false" ]

  # additionalContext should be present
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "true" ]
}

# ---------- Anti-Pattern Strings ----------

@test "output contains no anti-pattern strings" {
  local sid="test-session-stop-anti-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-anti >/dev/null 2>&1
  make_commit "feat: anti-pattern test"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]

  [[ ! "${output,,}" == *"use askuserquestion"* ]]
  [[ ! "${output,,}" == *"you must"* ]]
  [[ ! "${output,,}" == *"stop and"* ]]
  [[ ! "${output,,}" == *"do not proceed"* ]]
  [[ ! "${output,,}" == *"do not continue"* ]]
  [[ ! "${output,,}" == *"execute this command immediately"* ]]
}

# ---------- Output Brevity Rules ----------

@test "each additionalContext line starts with [git-pilot]" {
  local sid="test-session-stop-prefix-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-prefix >/dev/null 2>&1
  make_commit "feat: prefix test"

  run_hook "$TEST_REPO" "$sid"
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
  local sid="test-session-stop-len-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-len >/dev/null 2>&1
  make_commit "feat: length test"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  if [[ -n "$ctx" ]]; then
    while IFS= read -r line; do
      [ "${#line}" -lt 120 ]
    done <<< "$ctx"
  fi
}

@test "additionalContext has at most 5 lines" {
  local sid="test-session-stop-max5-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-max5 >/dev/null 2>&1
  make_commit "feat: max5 test"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  if [[ -n "$ctx" ]]; then
    local line_count
    line_count=$(echo "$ctx" | wc -l | tr -d ' ')
    [ "$line_count" -le 5 ]
  fi
}

# ---------- Condition: Session With Commits ----------

@test "session with commits: outputs session summary line" {
  local sid="test-session-stop-commits-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-commits >/dev/null 2>&1
  make_commit "feat: first change" "file1.txt"
  make_commit "feat: second change" "file2.txt"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] Session: 2 commit(s),"* ]]
  [[ "$ctx" == *"file(s) changed on 'feat/test-commits'"* ]]
}

@test "session summary uses commit count not commit listing" {
  local sid="test-session-stop-nolist-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-nolist >/dev/null 2>&1
  make_commit "feat: listed change" "listed.txt"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  # Must NOT contain commit hashes or per-commit details
  [[ ! "$ctx" == *"- "* ]]
  [[ ! "$ctx" == *"Commits ("* ]]
  [[ ! "$ctx" == *"Session Summary"* ]]
}

# ---------- Condition: No Commits In Session ----------

@test "no commits in session: silent exit with continue true" {
  local sid="test-session-stop-nochanges-$$"
  # Set headAtStart to current HEAD so no changes detected
  create_state "$sid"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]

  # No additionalContext when there are no changes
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "false" ]
}

# ---------- Condition: Unpushed Commits ----------

@test "unpushed commits: outputs remaining count" {
  setup_remote_repo

  local sid="test-session-stop-unpushed-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-unpushed >/dev/null 2>&1
  make_commit "feat: unpushed change"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"unpushed commit(s) remaining"* ]]
}

# ---------- Condition: Push Always Mode ----------

@test "push always mode: outputs auto-push line" {
  setup_remote_repo

  local sid="test-session-stop-push-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-push >/dev/null 2>&1
  make_commit "feat: push test"

  # Create config with pushOnFinish=always
  mkdir -p "$TEST_REPO/.claude"
  echo '{"remote":{"pushOnFinish":"always"}}' > "$TEST_REPO/.claude/git-pilot.json"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.additionalContext // ""')
  [[ "$ctx" == *"[git-pilot] Auto-push: run 'git push -u origin feat/test-push'"* ]]
}

# ---------- Non-Interactive Constraint Tests ----------

@test "output does not contain diff stat" {
  local sid="test-session-stop-nodiff-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-nodiff >/dev/null 2>&1
  make_commit "feat: diff test"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  # No diff --stat output, no file-level details, no insertion/deletion counts
  [[ ! "$output" == *"insertion"* ]]
  [[ ! "$output" == *"deletion"* ]]
  [[ ! "$output" == *" | "* ]]
}

@test "output does not contain MR body content" {
  local sid="test-session-stop-nomr-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-nomr >/dev/null 2>&1
  make_commit "feat: mr body test"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  # No MR body building artifacts
  [[ ! "$output" == *"## Summary"* ]]
  [[ ! "$output" == *"## Commits"* ]]
  [[ ! "$output" == *"## Files Changed"* ]]
  [[ ! "$output" == *"--title"* ]]
  [[ ! "$output" == *"--body"* ]]
  [[ ! "$output" == *"--description"* ]]
}

@test "output does not contain merge-fallback references" {
  local sid="test-session-stop-nomerge-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-nomerge >/dev/null 2>&1
  make_commit "feat: merge test"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  [[ ! "${output,,}" == *"merge-fallback"* ]]
  [[ ! "${output,,}" == *"fall back to merge"* ]]
}

# ---------- Agent Suppression ----------

@test "agent context via env var: silent exit with continue true" {
  local sid="test-session-stop-agent-env-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-agent-env >/dev/null 2>&1
  make_commit "feat: agent env test"

  # Set agent env var
  export CLAUDE_SPAWNED_BY="orchestrator"
  run_hook "$TEST_REPO" "$sid"
  unset CLAUDE_SPAWNED_BY

  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]

  # Agent path should NOT have additionalContext
  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "false" ]
}

@test "agent context via state file: silent exit with continue true" {
  local sid="test-session-stop-agent-state-$$"
  local old_head
  old_head=$(cd "$TEST_REPO" && git rev-parse HEAD)
  create_agent_state "$sid" "$old_head"

  cd "$TEST_REPO"
  git checkout -b feat/test-agent-state >/dev/null 2>&1
  make_commit "feat: agent state test"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]

  local has_ctx
  has_ctx=$(echo "$output" | jq 'has("additionalContext")')
  [ "$has_ctx" = "false" ]
}

# ---------- Error Resilience ----------

@test "not a git repo: exits silently with status 0" {
  local non_git_dir
  non_git_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/git-pilot-nongit.XXXXXX")"

  run_hook "$non_git_dir"
  [ "$status" -eq 0 ]
  # Should produce no output (exit 0 before any JSON)
  [ -z "$output" ]

  rm -rf "$non_git_dir"
}

@test "empty cwd: exits silently with status 0" {
  run bash -c 'bash "$1" 2>/dev/null <<< "$2"' _ \
    "$HOOK_SCRIPT" '{"cwd": "", "session_id": "test-empty"}'
  [ "$status" -eq 0 ]
}

@test "missing state file: produces valid JSON" {
  # Use a session_id that has no corresponding state file
  local sid="test-session-stop-nostate-$$"
  # Do NOT create a state file

  cd "$TEST_REPO"
  git checkout -b feat/test-nostate >/dev/null 2>&1
  make_commit "feat: no state test"

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
}

@test "missing session_id: produces valid JSON" {
  run bash -c 'bash "$1" 2>/dev/null <<< "$2"' _ \
    "$HOOK_SCRIPT" "{\"cwd\": \"${TEST_REPO}\"}"
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
  local continue_val
  continue_val=$(echo "$output" | jq -r '.continue')
  [ "$continue_val" = "true" ]
}

# ---------- State Cleanup ----------

@test "session state file is cleaned up after stop" {
  local sid="test-session-stop-cleanup-$$"
  create_state "$sid"

  local state_file="/tmp/git-pilot-${sid}.json"
  [ -f "$state_file" ]

  run_hook "$TEST_REPO" "$sid"
  [ "$status" -eq 0 ]

  # State file should be removed
  [ ! -f "$state_file" ]
}
