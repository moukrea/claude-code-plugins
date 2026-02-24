#!/usr/bin/env bats

# Tests for rebase.sh: attempt_rebase, get_conflict_details, needs_force_push.

load test_helper/common

setup() {
  setup_test_repo
  source_script "config.sh"
  source_script "state.sh"
  source_script "git-utils.sh"
  source_script "rebase.sh"
}

teardown() {
  # Abort any in-progress rebase to allow cleanup
  cd "$TEST_REPO" 2>/dev/null && git rebase --abort 2>/dev/null || true
  teardown_test_repo
}

# ---------- attempt_rebase ----------

@test "attempt_rebase: clean rebase succeeds" {
  setup_remote_repo

  cd "$TEST_REPO"
  # Create and switch to a feature branch
  git checkout -b feat/clean-rebase >/dev/null 2>&1
  echo "feature" > feature.txt
  git add feature.txt
  git commit -m "feat: add feature" >/dev/null 2>&1

  # Add a non-conflicting commit on main
  git checkout main >/dev/null 2>&1
  echo "main change" > main-change.txt
  git add main-change.txt
  git commit -m "feat: main change" >/dev/null 2>&1

  git checkout feat/clean-rebase >/dev/null 2>&1

  run attempt_rebase "main"
  [ "$status" -eq 0 ]
  [ "$output" = "success" ]
}

@test "attempt_rebase: reports conflict on conflicting changes" {
  setup_remote_repo

  cd "$TEST_REPO"
  # Modify the same file on main and feature branch
  echo "main version" > conflict-file.txt
  git add conflict-file.txt
  git commit -m "feat: main version" >/dev/null 2>&1

  git checkout -b feat/conflict HEAD~1 >/dev/null 2>&1
  echo "feature version" > conflict-file.txt
  git add conflict-file.txt
  git commit -m "feat: feature version" >/dev/null 2>&1

  run attempt_rebase "main"
  [ "$status" -eq 1 ]
  [ "$output" = "conflict" ]
}

@test "attempt_rebase: reports dirty worktree error" {
  cd "$TEST_REPO"
  echo "uncommitted" > dirty.txt

  run attempt_rebase "main"
  [ "$status" -eq 1 ]
  [ "$output" = "error:dirty-worktree" ]
}

# ---------- get_conflict_details ----------

@test "get_conflict_details: returns empty array when no conflicts" {
  cd "$TEST_REPO"
  run get_conflict_details
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "get_conflict_details: returns conflict info during rebase conflict" {
  cd "$TEST_REPO"
  # Create a conflict scenario
  echo "base content" > conflict-file.txt
  git add conflict-file.txt
  git commit -m "feat: base content" >/dev/null 2>&1

  git checkout -b feat/conflict-details HEAD~1 >/dev/null 2>&1
  echo "feature content" > conflict-file.txt
  git add conflict-file.txt
  git commit -m "feat: feature content" >/dev/null 2>&1

  # Attempt the rebase (will fail with conflict)
  git rebase main 2>/dev/null || true

  run get_conflict_details
  [ "$status" -eq 0 ]
  # Should be a non-empty JSON array
  [[ "$output" != "[]" ]]

  local file_count
  file_count=$(echo "$output" | jq 'length')
  [ "$file_count" -ge 1 ]

  local first_file
  first_file=$(echo "$output" | jq -r '.[0].file')
  [ "$first_file" = "conflict-file.txt" ]

  local conflict_type
  conflict_type=$(echo "$output" | jq -r '.[0].type')
  [ "$conflict_type" = "both-modified" ]
}

# ---------- needs_force_push ----------

@test "needs_force_push: returns false when no remote tracking branch" {
  # No remote at all
  cd "$TEST_REPO"
  run needs_force_push "main" "origin"
  [ "$status" -eq 1 ]
}

@test "needs_force_push: returns false when local is ahead (no rewrite)" {
  setup_remote_repo

  cd "$TEST_REPO"
  echo "ahead" > ahead.txt
  git add ahead.txt
  git commit -m "feat: ahead" >/dev/null 2>&1

  run needs_force_push "main" "origin"
  [ "$status" -eq 1 ]
}

@test "needs_force_push: returns true after history rewrite (rebase)" {
  setup_remote_repo

  cd "$TEST_REPO"
  # Create a feature branch and push it
  git checkout -b feat/force-push >/dev/null 2>&1
  echo "feature commit 1" > f1.txt
  git add f1.txt
  git commit -m "feat: commit 1" >/dev/null 2>&1
  git push -u origin feat/force-push >/dev/null 2>&1

  # Add a commit on main
  git checkout main >/dev/null 2>&1
  echo "main commit" > m1.txt
  git add m1.txt
  git commit -m "feat: main commit" >/dev/null 2>&1

  # Rebase feature onto main (rewrites history)
  git checkout feat/force-push >/dev/null 2>&1
  git rebase main >/dev/null 2>&1

  run needs_force_push "feat/force-push" "origin"
  [ "$status" -eq 0 ]
}

@test "needs_force_push: returns false when local matches remote" {
  setup_remote_repo

  cd "$TEST_REPO"
  run needs_force_push "main" "origin"
  [ "$status" -eq 1 ]
}
