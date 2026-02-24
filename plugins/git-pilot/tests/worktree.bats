#!/usr/bin/env bats

# Tests for worktree.sh: create_worktree, remove_worktree, list_worktrees,
# merge_worktree_branch.

load test_helper/common

setup() {
  setup_test_repo
  # worktree.sh sources config.sh internally via SCRIPT_DIR, so we just need
  # to ensure the git repo is set up.  We source it after cd into the test repo.
  source_script "config.sh"
  source_script "state.sh"
  source_script "git-utils.sh"

  # worktree.sh computes WORKTREE_REGISTRY at source time using git rev-parse.
  # We must be in the test repo when we source it.
  cd "$TEST_REPO"
  source_script "worktree.sh"
}

teardown() {
  # Clean up any worktrees that might have been created
  cd "$TEST_REPO" 2>/dev/null || true
  git worktree list --porcelain 2>/dev/null | grep '^worktree ' | while read -r _ path; do
    if [[ "$path" != "$TEST_REPO" ]]; then
      git worktree remove --force "$path" 2>/dev/null || true
    fi
  done
  teardown_test_repo
}

# ---------- Helper ----------

_default_config() {
  cat "$PLUGIN_DIR/defaults/config.json"
}

# ---------- create_worktree ----------

@test "create_worktree: creates worktree and registers in registry" {
  cd "$TEST_REPO"
  local config
  config=$(_default_config)

  run create_worktree "$config" "feat/new-worktree" "main" "session-wt-1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"feat-new-worktree"* ]]

  # Verify the worktree directory exists
  local wt_path="$output"
  [ -d "$wt_path" ]

  # Verify registry entry
  [ -f "$WORKTREE_REGISTRY" ]
  local branch_in_registry
  branch_in_registry=$(jq -r '.worktrees[0].branch' "$WORKTREE_REGISTRY")
  [ "$branch_in_registry" = "feat/new-worktree" ]

  local status_in_registry
  status_in_registry=$(jq -r '.worktrees[0].status' "$WORKTREE_REGISTRY")
  [ "$status_in_registry" = "active" ]
}

@test "create_worktree: records session ID in registry" {
  cd "$TEST_REPO"
  local config
  config=$(_default_config)

  run create_worktree "$config" "feat/session-tracked" "main" "my-session-42"
  [ "$status" -eq 0 ]

  local sid
  sid=$(jq -r '.worktrees[0].createdBy' "$WORKTREE_REGISTRY")
  [ "$sid" = "my-session-42" ]
}

@test "create_worktree: fails when branch already exists" {
  cd "$TEST_REPO"
  local config
  config=$(_default_config)

  # Create a branch first
  git branch feat/existing-branch >/dev/null 2>&1

  # Trying to create a worktree with -b for an existing branch should fail
  run create_worktree "$config" "feat/existing-branch" "main"
  [ "$status" -eq 1 ]
}

# ---------- remove_worktree ----------

@test "remove_worktree: removes worktree and unregisters from registry" {
  cd "$TEST_REPO"
  local config
  config=$(_default_config)

  local wt_path
  wt_path=$(create_worktree "$config" "feat/to-remove" "main")

  # Verify it exists
  [ -d "$wt_path" ]
  local count_before
  count_before=$(jq '.worktrees | length' "$WORKTREE_REGISTRY")
  [ "$count_before" = "1" ]

  run remove_worktree "$wt_path"
  [ "$status" -eq 0 ]

  # Verify worktree is gone
  [ ! -d "$wt_path" ]

  # Verify registry is empty
  local count_after
  count_after=$(jq '.worktrees | length' "$WORKTREE_REGISTRY")
  [ "$count_after" = "0" ]
}

@test "remove_worktree: force removal succeeds with uncommitted changes" {
  cd "$TEST_REPO"
  local config
  config=$(_default_config)

  local wt_path
  wt_path=$(create_worktree "$config" "feat/dirty-wt" "main")

  # Create uncommitted changes in the worktree
  echo "dirty" > "$wt_path/dirty-file.txt"
  cd "$wt_path"
  git add dirty-file.txt
  cd "$TEST_REPO"

  run remove_worktree "$wt_path" "true"
  [ "$status" -eq 0 ]
}

# ---------- list_worktrees ----------

@test "list_worktrees: returns empty structure when no worktrees registered" {
  cd "$TEST_REPO"
  run list_worktrees
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq '.worktrees | length')
  [ "$count" = "0" ]
}

@test "list_worktrees: returns registered worktrees" {
  cd "$TEST_REPO"
  local config
  config=$(_default_config)

  create_worktree "$config" "feat/wt-list-1" "main" >/dev/null
  create_worktree "$config" "feat/wt-list-2" "main" >/dev/null

  run list_worktrees
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq '.worktrees | length')
  [ "$count" = "2" ]
}

# ---------- merge_worktree_branch ----------

@test "merge_worktree_branch: merges branch and cleans up worktree" {
  cd "$TEST_REPO"
  local config
  config=$(_default_config)

  local wt_path
  wt_path=$(create_worktree "$config" "feat/to-merge" "main")

  # Make a commit in the worktree
  cd "$wt_path"
  echo "merge me" > merge-file.txt
  git add merge-file.txt
  git commit -m "feat: merge file" >/dev/null 2>&1
  cd "$TEST_REPO"

  run merge_worktree_branch "$wt_path" "main" "$config"
  [ "$status" -eq 0 ]
  [ "$output" = "success" ]

  # Verify the merge file exists on main
  [ -f "$TEST_REPO/merge-file.txt" ]

  # With cleanupOnMerge=true (default), worktree should be removed
  [ ! -d "$wt_path" ]
}

@test "merge_worktree_branch: reports conflict on conflicting merge" {
  cd "$TEST_REPO"
  local config
  config=$(_default_config)

  local wt_path
  wt_path=$(create_worktree "$config" "feat/conflict-merge" "main")

  # Modify the same file in the worktree
  cd "$wt_path"
  echo "worktree version" > README.md
  git add README.md
  git commit -m "feat: worktree change" >/dev/null 2>&1

  # Modify the same file on main
  cd "$TEST_REPO"
  echo "main version" > README.md
  git add README.md
  git commit -m "feat: main change" >/dev/null 2>&1

  run merge_worktree_branch "$wt_path" "main" "$config"
  [ "$status" -eq 1 ]
  [ "$output" = "conflict" ]

  # Clean up the failed merge
  git merge --abort 2>/dev/null || true
}
