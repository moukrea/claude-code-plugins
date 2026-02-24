#!/usr/bin/env bats

# Tests for auto_stash() and auto_restore_stash() from git-utils.sh.

load test_helper/common

setup() {
  setup_test_repo
  source_script "config.sh"
  source_script "state.sh"
  source_script "git-utils.sh"
}

teardown() {
  rm -f /tmp/git-pilot-test-stash-*.json
  teardown_test_repo
}

# ---------- auto_stash ----------

@test "auto_stash: stashes uncommitted changes and records in state" {
  cd "$TEST_REPO"
  local sid="test-stash-auto"
  init_state "$sid" "main" ""

  # Create uncommitted changes
  echo "dirty content" > dirty-file.txt
  git add dirty-file.txt

  run auto_stash "main" "$sid"
  [ "$status" -eq 0 ]

  # Verify the stash was created
  local stash_count
  stash_count=$(git stash list | wc -l)
  [ "$stash_count" -ge 1 ]

  # Verify state was updated with stash ref
  local state_file
  state_file=$(get_state_file "$sid")
  local stash_refs_count
  stash_refs_count=$(cat "$state_file" | jq '.stashRefs | length')
  [ "$stash_refs_count" = "1" ]

  local stash_branch
  stash_branch=$(cat "$state_file" | jq -r '.stashRefs[0].branch')
  [ "$stash_branch" = "main" ]

  rm -f "$state_file"
}

@test "auto_stash: returns 1 when there is nothing to stash" {
  cd "$TEST_REPO"
  local sid="test-stash-clean"
  init_state "$sid" "main" ""

  run auto_stash "main" "$sid"
  [ "$status" -eq 1 ]

  local state_file
  state_file=$(get_state_file "$sid")
  rm -f "$state_file"
}

@test "auto_stash: stash message includes branch name" {
  cd "$TEST_REPO"
  local sid="test-stash-msg"
  init_state "$sid" "feat/my-feature" ""

  echo "changes" > stash-test.txt
  git add stash-test.txt

  auto_stash "feat/my-feature" "$sid"

  local stash_msg
  stash_msg=$(git stash list --format='%s' | head -1)
  [[ "$stash_msg" == *"feat/my-feature"* ]]

  local state_file
  state_file=$(get_state_file "$sid")
  rm -f "$state_file"
}

# ---------- auto_restore_stash ----------

@test "auto_restore_stash: restores stash and removes from state" {
  cd "$TEST_REPO"
  local sid="test-restore-ok"
  init_state "$sid" "main" ""

  # Create changes and stash them
  echo "restore me" > restore-file.txt
  git add restore-file.txt
  auto_stash "main" "$sid"

  # Verify file is gone from working tree
  [ ! -f "restore-file.txt" ] || [ -z "$(git status --porcelain)" ]

  # Restore the stash
  run auto_restore_stash "main" "$sid"
  [ "$status" -eq 0 ]

  # Verify file is back
  [ -f "restore-file.txt" ]

  # Verify state no longer has the stash ref
  local state_file
  state_file=$(get_state_file "$sid")
  local stash_refs_count
  stash_refs_count=$(cat "$state_file" | jq '.stashRefs | length')
  [ "$stash_refs_count" = "0" ]

  rm -f "$state_file"
}

@test "auto_restore_stash: returns 1 when no stash exists for branch" {
  cd "$TEST_REPO"
  local sid="test-restore-none"
  init_state "$sid" "main" ""

  run auto_restore_stash "feat/no-stash" "$sid"
  [ "$status" -eq 1 ]

  local state_file
  state_file=$(get_state_file "$sid")
  rm -f "$state_file"
}

@test "auto_restore_stash: returns 1 when session_id is empty" {
  cd "$TEST_REPO"
  run auto_restore_stash "main" ""
  [ "$status" -eq 1 ]
}

@test "auto_restore_stash: fails gracefully when stash pop conflicts" {
  cd "$TEST_REPO"
  local sid="test-restore-conflict"
  init_state "$sid" "main" ""

  # Stash a change to a tracked file
  echo "stashed version" > README.md
  git add README.md
  auto_stash "main" "$sid"

  # Now modify the same file so the pop will conflict
  echo "conflicting version" > README.md
  git add README.md
  git commit -m "feat: conflicting change" >/dev/null 2>&1

  # The stash pop should fail due to conflict
  run auto_restore_stash "main" "$sid"
  [ "$status" -eq 1 ]

  local state_file
  state_file=$(get_state_file "$sid")
  rm -f "$state_file"
}
