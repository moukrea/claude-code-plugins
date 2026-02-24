#!/usr/bin/env bats

# Tests for protected branch enforcement in pre-commit.sh.
# We test the normalize_protect_default_branch function (from config.sh)
# and the branch protection logic by invoking the pre-commit hook script
# with crafted JSON input.

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

# Helper: create a local git-pilot config with a specific protectDefaultBranch value.
_set_protect_mode() {
  local mode="$1"
  create_config "$TEST_REPO/.claude/git-pilot.json" "{\"git\":{\"protectDefaultBranch\":$mode}}"
}

# Helper: run the pre-commit hook with a git commit command.
# This pipes the expected JSON input into the hook script.
_run_pre_commit() {
  local command="${1:-git commit -m \"feat: test commit\"}"
  local input
  input=$(jq -n \
    --arg sid "test-session" \
    --arg tool "Bash" \
    --arg cmd "$command" \
    --arg cwd "$TEST_REPO" \
    '{session_id:$sid, tool_name:$tool, tool_input:{command:$cmd}, cwd:$cwd}')

  echo "$input" | bash "$SCRIPTS_DIR/pre-commit.sh" 2>&1
  return "${PIPESTATUS[1]}"
}

# ---------- warn mode ----------

@test "protected-branch warn mode: warning emitted, commit allowed" {
  cd "$TEST_REPO"
  _set_protect_mode '"warn"'

  # We are on main (the default branch)
  local output
  output=$(_run_pre_commit) || true

  # Should contain a warning message
  [[ "$output" == *"Warning"* ]] || [[ "$output" == *"warn"* ]] || [[ "$output" == *"committing directly"* ]]
}

@test "protected-branch warn mode: exits with 0 (allow)" {
  cd "$TEST_REPO"
  _set_protect_mode '"warn"'

  local exit_code=0
  _run_pre_commit >/dev/null 2>&1 || exit_code=$?
  [ "$exit_code" -eq 0 ]
}

# ---------- block mode ----------

@test "protected-branch block mode: commit blocked with exit code 2" {
  cd "$TEST_REPO"
  _set_protect_mode '"block"'

  local exit_code=0
  local output
  output=$(_run_pre_commit 2>&1) || exit_code=$?
  [ "$exit_code" -eq 2 ]
  [[ "$output" == *"blocked"* ]] || [[ "$output" == *"block"* ]]
}

# ---------- off mode ----------

@test "protected-branch off mode: no warning, commit allowed" {
  cd "$TEST_REPO"
  _set_protect_mode '"off"'

  local exit_code=0
  local output
  output=$(_run_pre_commit 2>&1) || exit_code=$?
  [ "$exit_code" -eq 0 ]
  # Should NOT contain any warning about default branch
  [[ "$output" != *"Warning: You are committing directly"* ]]
}

# ---------- boolean backward compatibility ----------

@test "protected-branch boolean true: treated as warn" {
  cd "$TEST_REPO"
  _set_protect_mode 'true'

  local exit_code=0
  local output
  output=$(_run_pre_commit 2>&1) || exit_code=$?

  # Should be allowed (exit 0) but with a warning
  [ "$exit_code" -eq 0 ]
  [[ "$output" == *"Warning"* ]] || [[ "$output" == *"committing directly"* ]]
}

@test "protected-branch boolean false: treated as off" {
  cd "$TEST_REPO"
  _set_protect_mode 'false'

  local exit_code=0
  local output
  output=$(_run_pre_commit 2>&1) || exit_code=$?
  [ "$exit_code" -eq 0 ]
  [[ "$output" != *"Warning: You are committing directly"* ]]
}

# ---------- non-default branch ----------

@test "protected-branch: no enforcement on feature branch" {
  cd "$TEST_REPO"
  _set_protect_mode '"block"'

  # Switch to a feature branch
  git checkout -b feat/safe-branch >/dev/null 2>&1
  echo "change" > safe.txt
  git add safe.txt

  local exit_code=0
  _run_pre_commit >/dev/null 2>&1 || exit_code=$?
  [ "$exit_code" -eq 0 ]
}
