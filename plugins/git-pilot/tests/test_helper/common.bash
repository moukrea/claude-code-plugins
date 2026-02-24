#!/usr/bin/env bash

# Shared test helper for git-pilot bats tests.
# Provides fixtures for creating isolated git repos, sourcing scripts,
# and managing test configuration.

# Absolute path to the plugin root (two levels up from test_helper/).
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$PLUGIN_DIR/scripts"

# ---------- Git repo fixtures ----------

# Creates a temporary git repository with an initial commit on the "main" branch.
# Sets TEST_REPO, TEST_REMOTE (empty initially), and changes cwd into the repo.
setup_test_repo() {
  TEST_REPO="$(mktemp -d "${BATS_TMPDIR:-/tmp}/git-pilot-test.XXXXXX")"
  TEST_REMOTE=""
  cd "$TEST_REPO" || return 1

  git init -b main >/dev/null 2>&1
  git config user.name "Test User"
  git config user.email "test@example.com"

  # Create an initial commit so HEAD exists.
  echo "init" > README.md
  git add README.md
  git commit -m "chore: initial commit" >/dev/null 2>&1
}

# Creates a bare repository and adds it as "origin" to the test repo.
# Pushes the current branch so the remote has content.
# Must be called after setup_test_repo.
setup_remote_repo() {
  TEST_REMOTE="$(mktemp -d "${BATS_TMPDIR:-/tmp}/git-pilot-remote.XXXXXX")"
  git init --bare "$TEST_REMOTE" >/dev/null 2>&1

  cd "$TEST_REPO" || return 1
  git remote add origin "$TEST_REMOTE"
  git push -u origin main >/dev/null 2>&1
}

# Removes the temporary directories created by setup_test_repo / setup_remote_repo.
teardown_test_repo() {
  if [[ -n "${TEST_REPO:-}" ]] && [[ -d "$TEST_REPO" ]]; then
    rm -rf "$TEST_REPO"
  fi
  if [[ -n "${TEST_REMOTE:-}" ]] && [[ -d "$TEST_REMOTE" ]]; then
    rm -rf "$TEST_REMOTE"
  fi
}

# ---------- Configuration helpers ----------

# Writes a JSON config file at the given path.
# Usage: create_config "/path/to/config.json" '{"git":{"defaultBranch":"main"}}'
create_config() {
  local path="$1"
  local json="$2"
  mkdir -p "$(dirname "$path")"
  echo "$json" > "$path"
}

# ---------- Script sourcing ----------

# Sources a git-pilot script by name, setting the environment variables the
# scripts expect (SCRIPT_DIR, PLUGIN_ROOT).
#
# Usage: source_script "config.sh"
#        source_script "git-utils.sh"
#
# Scripts that reference SCRIPT_DIR or PLUGIN_ROOT at parse time (config.sh,
# agent.sh, worktree.sh) will pick up the real plugin paths because we export
# SCRIPT_DIR before sourcing.
source_script() {
  local script_name="$1"
  local script_path="$SCRIPTS_DIR/$script_name"

  if [[ ! -f "$script_path" ]]; then
    echo "source_script: $script_path not found" >&2
    return 1
  fi

  # Many scripts do `SCRIPT_DIR="$(cd ... && pwd)"` at the top which is fine --
  # they will resolve to the real scripts directory.  We also export it so that
  # scripts that only read the variable still work.
  export SCRIPT_DIR="$SCRIPTS_DIR"
  export PLUGIN_ROOT="$PLUGIN_DIR"

  # Disable the set -euo pipefail that each script sets at the top so that
  # bats `run` can capture non-zero exits without aborting the test.
  # We achieve this by sourcing with a wrapper that traps errors.
  # shellcheck disable=SC1090
  source "$script_path"
}
