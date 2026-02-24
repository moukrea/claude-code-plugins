#!/usr/bin/env bats

# Tests for git-utils.sh: get_branch_tracking_status, fetch_with_retry,
# derive_branch_purpose, is_detached_head.

load test_helper/common

setup() {
  setup_test_repo
  source_script "config.sh"
  source_script "state.sh"
  source_script "git-utils.sh"
}

teardown() {
  teardown_test_repo
}

# ---------- get_branch_tracking_status ----------

@test "get_branch_tracking_status: up-to-date when local matches remote" {
  setup_remote_repo

  run get_branch_tracking_status "main" "origin"
  [ "$status" -eq 0 ]
  [ "$output" = "up-to-date" ]
}

@test "get_branch_tracking_status: behind when remote has new commits" {
  setup_remote_repo

  # Clone elsewhere and push a commit
  local clone_dir
  clone_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/git-pilot-clone.XXXXXX")"
  git clone "$TEST_REMOTE" "$clone_dir" >/dev/null 2>&1
  cd "$clone_dir"
  git config user.name "Other"
  git config user.email "other@example.com"
  echo "remote change" > remote-file.txt
  git add remote-file.txt
  git commit -m "feat: remote change" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  # Back in test repo, fetch so we know about the remote commit
  cd "$TEST_REPO"
  git fetch origin >/dev/null 2>&1

  run get_branch_tracking_status "main" "origin"
  [ "$status" -eq 0 ]
  [[ "$output" == behind:* ]]

  rm -rf "$clone_dir"
}

@test "get_branch_tracking_status: ahead when local has unpushed commits" {
  setup_remote_repo

  cd "$TEST_REPO"
  echo "local change" > local-file.txt
  git add local-file.txt
  git commit -m "feat: local change" >/dev/null 2>&1

  run get_branch_tracking_status "main" "origin"
  [ "$status" -eq 0 ]
  [[ "$output" == ahead:* ]]
}

@test "get_branch_tracking_status: diverged when both sides have new commits" {
  setup_remote_repo

  # Push a commit from a clone
  local clone_dir
  clone_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/git-pilot-clone.XXXXXX")"
  git clone "$TEST_REMOTE" "$clone_dir" >/dev/null 2>&1
  cd "$clone_dir"
  git config user.name "Other"
  git config user.email "other@example.com"
  echo "remote diverge" > diverge-remote.txt
  git add diverge-remote.txt
  git commit -m "feat: remote diverge" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  # Make a local commit in test repo
  cd "$TEST_REPO"
  git fetch origin >/dev/null 2>&1
  echo "local diverge" > diverge-local.txt
  git add diverge-local.txt
  git commit -m "feat: local diverge" >/dev/null 2>&1

  run get_branch_tracking_status "main" "origin"
  [ "$status" -eq 0 ]
  [[ "$output" == diverged:* ]]

  rm -rf "$clone_dir"
}

@test "get_branch_tracking_status: no-remote when remote branch does not exist" {
  # No remote set up at all
  run get_branch_tracking_status "main" "origin"
  [ "$status" -eq 0 ]
  [ "$output" = "no-remote" ]
}

# ---------- fetch_with_retry ----------

@test "fetch_with_retry: succeeds on valid remote" {
  setup_remote_repo

  local config='{"git":{"fetchRetries":1,"fetchRetryDelaySec":0}}'
  run fetch_with_retry "origin" "$config"
  [ "$status" -eq 0 ]
}

@test "fetch_with_retry: fails after retries on invalid remote" {
  # Add a bogus remote
  git remote add bogus "file:///nonexistent/path/to/repo"

  local config='{"git":{"fetchRetries":0,"fetchRetryDelaySec":0}}'
  run fetch_with_retry "bogus" "$config"
  [ "$status" -eq 1 ]
}

@test "fetch_with_retry: fetches specific branch" {
  setup_remote_repo

  local config='{"git":{"fetchRetries":1,"fetchRetryDelaySec":0}}'
  run fetch_with_retry "origin" "$config" "main"
  [ "$status" -eq 0 ]
}

# ---------- derive_branch_purpose ----------

@test "derive_branch_purpose: strips type prefix and converts kebab-case" {
  run derive_branch_purpose "feat/add-dark-mode"
  [ "$status" -eq 0 ]
  [ "$output" = "add dark mode" ]
}

@test "derive_branch_purpose: converts snake_case to words" {
  run derive_branch_purpose "fix/login_timeout_bug"
  [ "$status" -eq 0 ]
  [ "$output" = "login timeout bug" ]
}

@test "derive_branch_purpose: handles branch with no type prefix" {
  run derive_branch_purpose "simple-branch"
  [ "$status" -eq 0 ]
  [ "$output" = "simple branch" ]
}

@test "derive_branch_purpose: handles nested slashes by stripping first segment" {
  run derive_branch_purpose "feat/api/auth-endpoints"
  [ "$status" -eq 0 ]
  # sed strips everything up to and including the first /
  [[ "$output" == *"auth endpoints"* ]]
}

# ---------- is_detached_head ----------

@test "is_detached_head: returns false on normal branch" {
  run is_detached_head
  [ "$status" -eq 1 ]
}

@test "is_detached_head: returns true in detached HEAD state" {
  local head_sha
  head_sha=$(git rev-parse HEAD)
  git checkout "$head_sha" >/dev/null 2>&1

  run is_detached_head
  [ "$status" -eq 0 ]
}
