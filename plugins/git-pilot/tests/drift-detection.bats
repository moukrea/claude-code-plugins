#!/usr/bin/env bats

# Tests for rebase.sh: get_base_branch_drift (base branch drift detection).

load test_helper/common

setup() {
  setup_test_repo
  source_script "config.sh"
  source_script "state.sh"
  source_script "git-utils.sh"
  source_script "rebase.sh"
}

teardown() {
  teardown_test_repo
}

# ---------- get_base_branch_drift ----------

@test "get_base_branch_drift: no drift when base has no new commits" {
  setup_remote_repo

  # Create a feature branch from main
  cd "$TEST_REPO"
  git checkout -b feat/my-feature >/dev/null 2>&1
  echo "feature work" > feature.txt
  git add feature.txt
  git commit -m "feat: add feature" >/dev/null 2>&1

  run get_base_branch_drift "feat/my-feature" "main" "origin"
  [ "$status" -eq 0 ]
  [ "$output" = "no-drift" ]
}

@test "get_base_branch_drift: detects drift when base branch has new commits" {
  setup_remote_repo

  # Create a feature branch
  cd "$TEST_REPO"
  git checkout -b feat/my-feature >/dev/null 2>&1
  echo "feature work" > feature.txt
  git add feature.txt
  git commit -m "feat: add feature" >/dev/null 2>&1

  # Push a new commit to main on the remote
  local clone_dir
  clone_dir="$(mktemp -d "${BATS_TMPDIR:-/tmp}/git-pilot-clone.XXXXXX")"
  git clone "$TEST_REMOTE" "$clone_dir" >/dev/null 2>&1
  cd "$clone_dir"
  git config user.name "Other"
  git config user.email "other@example.com"
  echo "base change" > base-change.txt
  git add base-change.txt
  git commit -m "feat: base change" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  cd "$TEST_REPO"
  run get_base_branch_drift "feat/my-feature" "main" "origin"
  [ "$status" -eq 0 ]
  [[ "$output" == drifted:* ]]

  rm -rf "$clone_dir"
}

@test "get_base_branch_drift: returns no-common-ancestor for orphan branches" {
  setup_remote_repo

  # Create an orphan branch with no common history
  cd "$TEST_REPO"
  git checkout --orphan orphan-branch >/dev/null 2>&1
  git rm -rf . >/dev/null 2>&1
  echo "orphan content" > orphan.txt
  git add orphan.txt
  git commit -m "chore: orphan init" >/dev/null 2>&1

  # Push the orphan branch to remote so fetch succeeds
  git push origin orphan-branch >/dev/null 2>&1

  # Now try to detect drift between orphan-branch and main
  # The orphan branch itself shares no history with main
  run get_base_branch_drift "orphan-branch" "main" "origin"
  [ "$status" -eq 0 ]
  [ "$output" = "no-common-ancestor" ]
}

@test "get_base_branch_drift: returns error when fetch fails" {
  # No remote set up, so fetch will fail
  cd "$TEST_REPO"
  git checkout -b feat/no-remote >/dev/null 2>&1

  run get_base_branch_drift "feat/no-remote" "main" "origin"
  [ "$status" -eq 1 ]
}
