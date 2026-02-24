#!/usr/bin/env bats

# Tests for state.sh: get_state_file, init_state, read_state, update_state,
# write_state, cleanup_state.

load test_helper/common

setup() {
  setup_test_repo
  source_script "config.sh"
  source_script "state.sh"
}

teardown() {
  # Clean up any state files created during the test
  rm -f /tmp/git-pilot-test-session-*.json
  teardown_test_repo
}

# ---------- get_state_file ----------

@test "get_state_file: returns expected path pattern" {
  run get_state_file "abc123"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/git-pilot-abc123.json" ]
}

# ---------- read_state ----------

@test "read_state: returns empty object when file does not exist" {
  run read_state "/tmp/git-pilot-nonexistent-12345.json"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "read_state: returns content of valid JSON file" {
  local state_file="/tmp/git-pilot-test-session-read.json"
  echo '{"sessionId":"s1","changeCount":0}' > "$state_file"

  run read_state "$state_file"
  [ "$status" -eq 0 ]
  local sid
  sid=$(echo "$output" | jq -r '.sessionId')
  [ "$sid" = "s1" ]
}

@test "read_state: returns empty object for invalid JSON" {
  local state_file="/tmp/git-pilot-test-session-invalid.json"
  echo "not valid json {{{" > "$state_file"

  run read_state "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

# ---------- init_state (3-arg: session_id, working_branch, previous_branch) ----------

@test "init_state: creates state file with 3 args" {
  local sid="test-session-3arg"
  init_state "$sid" "feat/my-feature" "main"

  local state_file
  state_file=$(get_state_file "$sid")
  [ -f "$state_file" ]

  local content
  content=$(cat "$state_file")

  local session_id
  session_id=$(echo "$content" | jq -r '.sessionId')
  [ "$session_id" = "$sid" ]

  local wb
  wb=$(echo "$content" | jq -r '.workingBranch')
  [ "$wb" = "feat/my-feature" ]

  local pb
  pb=$(echo "$content" | jq -r '.previousBranch')
  [ "$pb" = "main" ]

  # base_branch and branchPurpose should be empty strings
  local bb
  bb=$(echo "$content" | jq -r '.baseBranch')
  [ "$bb" = "" ]

  rm -f "$state_file"
}

# ---------- init_state (5-arg: session_id, working_branch, previous_branch, base_branch, branch_purpose) ----------

@test "init_state: creates state file with 5 args" {
  local sid="test-session-5arg"
  init_state "$sid" "fix/login-bug" "develop" "main" "fix login timeout"

  local state_file
  state_file=$(get_state_file "$sid")
  [ -f "$state_file" ]

  local content
  content=$(cat "$state_file")

  local bb
  bb=$(echo "$content" | jq -r '.baseBranch')
  [ "$bb" = "main" ]

  local bp
  bp=$(echo "$content" | jq -r '.branchPurpose')
  [ "$bp" = "fix login timeout" ]

  # Verify new fields exist with correct defaults
  local change_count
  change_count=$(echo "$content" | jq -r '.changeCount')
  [ "$change_count" = "0" ]

  local is_agent
  is_agent=$(echo "$content" | jq -r '.isAgent')
  [ "$is_agent" = "false" ]

  local stash_refs
  stash_refs=$(echo "$content" | jq -r '.stashRefs | length')
  [ "$stash_refs" = "0" ]

  local active_worktrees
  active_worktrees=$(echo "$content" | jq -r '.activeWorktrees | length')
  [ "$active_worktrees" = "0" ]

  rm -f "$state_file"
}

@test "init_state: records headAtStart from current HEAD" {
  local sid="test-session-head"
  local expected_head
  expected_head=$(git rev-parse HEAD)

  init_state "$sid" "main" ""

  local state_file
  state_file=$(get_state_file "$sid")
  local head_at_start
  head_at_start=$(cat "$state_file" | jq -r '.headAtStart')
  [ "$head_at_start" = "$expected_head" ]

  rm -f "$state_file"
}

# ---------- update_state ----------

@test "update_state: increments changeCount" {
  local sid="test-session-update"
  init_state "$sid" "main" ""

  local state_file
  state_file=$(get_state_file "$sid")

  update_state "$state_file" '.changeCount += 1'

  local count
  count=$(cat "$state_file" | jq -r '.changeCount')
  [ "$count" = "1" ]

  # Increment again
  update_state "$state_file" '.changeCount += 1'
  count=$(cat "$state_file" | jq -r '.changeCount')
  [ "$count" = "2" ]

  rm -f "$state_file"
}

@test "update_state: sets isAgent to true with jq args" {
  local sid="test-session-agent"
  init_state "$sid" "main" ""

  local state_file
  state_file=$(get_state_file "$sid")

  update_state "$state_file" '.isAgent = true'

  local is_agent
  is_agent=$(cat "$state_file" | jq -r '.isAgent')
  [ "$is_agent" = "true" ]

  rm -f "$state_file"
}

@test "update_state: appends to modifiedFiles array" {
  local sid="test-session-files"
  init_state "$sid" "main" ""

  local state_file
  state_file=$(get_state_file "$sid")

  update_state "$state_file" --arg f "src/app.ts" '.modifiedFiles += [$f]'

  local files_count
  files_count=$(cat "$state_file" | jq '.modifiedFiles | length')
  [ "$files_count" = "1" ]

  local first_file
  first_file=$(cat "$state_file" | jq -r '.modifiedFiles[0]')
  [ "$first_file" = "src/app.ts" ]

  rm -f "$state_file"
}

# ---------- cleanup_state ----------

@test "cleanup_state: removes the state file" {
  local sid="test-session-cleanup"
  init_state "$sid" "main" ""

  local state_file
  state_file=$(get_state_file "$sid")
  [ -f "$state_file" ]

  cleanup_state "$state_file"
  [ ! -f "$state_file" ]
}
