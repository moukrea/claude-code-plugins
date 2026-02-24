# Task 019: Test Suite — Bats Tests for All New Functions and Scenarios

## Status
done

## Dependencies
- 001-config-schema (tests for config backward compatibility and normalization)
- 002-state-schema (tests for extended state fields)
- 003-git-utils-extensions (tests for branch freshness, fetch_with_retry, derive_branch_purpose)
- 004-agent-library (tests for agent detection)
- 005-rebase-library (tests for rebase, drift detection, conflict details)
- 006-worktree-library (tests for worktree CRUD and registry)
- 007-stash-functions (tests for auto_stash and auto_restore_stash)
- 008-hook-session-start (integration tests reference session-start behavior)
- 009-hook-pre-commit (tests for protected branch enforcement)
- 010-hook-post-bash (integration tests reference post-bash behavior)
- 011-hook-post-write (integration tests reference post-write behavior)
- 012-hook-session-stop (integration tests reference session-stop behavior)
- 013-hook-prompt-context (integration tests reference prompt-context behavior)
- 014-hook-registration (hooks.json must be finalized)
- 015-skills-modified (skills must be finalized for integration test context)
- 016-skills-new (skills must be finalized for integration test context)
- 017-claude-md-update (CLAUDE.md must be finalized)
- 018-plugin-metadata (plugin.json must be at 2.0.0)

## Spec References
- spec/01-config-and-state.md
- spec/02-git-utils-and-network.md
- spec/03-rebase-and-conflicts.md
- spec/04-agent-and-worktree.md
- spec/05-stash-and-robustness.md
- spec/06-hooks-and-lifecycle.md
- spec/07-skills-and-claude-md.md

## Scope
Create the full bats-core test suite for git-pilot v2. This includes a shared test helper with common fixtures (temporary git repo setup, config helpers, state helpers) and 8 test files covering all new functions and key scenarios specified in the tech spec section 8.2 and 8.3.

## Acceptance Criteria
- [ ] `plugins/git-pilot/tests/test_helper/common.bash` exists with shared setup/teardown fixtures that create temporary git repos with controlled state.
- [x] All 8 test files exist: `branch-freshness.bats`, `drift-detection.bats`, `rebase.bats`, `agent-detection.bats`, `worktree.bats`, `stash.bats`, `protected-branch.bats`, `config-compat.bats`.
- [ ] Each `.bats` file sources the appropriate script under test and the shared helper.
- [ ] Each test scenario from spec section 8.2 has a corresponding `@test` block.
- [ ] All tests can be run with `bats plugins/git-pilot/tests/` (assuming bats-core is installed).
- [ ] Tests use temporary directories (cleaned up in teardown) and do not modify the real repository.

## Implementation Notes

### Test Framework

Use `bats-core` (Bash Automated Testing System), version >= 1.0. Tests are run with:

```bash
bats plugins/git-pilot/tests/
```

### Directory Structure

```
plugins/git-pilot/tests/
├── test_helper/
│   └── common.bash
├── branch-freshness.bats
├── drift-detection.bats
├── rebase.bats
├── agent-detection.bats
├── worktree.bats
├── stash.bats
├── protected-branch.bats
└── config-compat.bats
```

### Shared Test Helper: `test_helper/common.bash`

The helper must provide:

1. **`setup_test_repo()`** — Create a temporary git repository in `$BATS_TMPDIR`, initialize it, create an initial commit, set up a `main` branch, configure user.name and user.email. Set `TEST_REPO` to the path.
2. **`setup_remote_repo()`** — Create a bare repo to act as a remote, add it as `origin` to the test repo.
3. **`teardown_test_repo()`** — Remove the temporary directories.
4. **`create_config()`** — Write a test config JSON to a specified path.
5. **`source_script()`** — Source a git-pilot script with the necessary environment variables set (`SCRIPT_DIR`, etc.).
6. **Common variables**: `PLUGIN_DIR` pointing to `plugins/git-pilot/`, `SCRIPTS_DIR` pointing to `plugins/git-pilot/scripts/`.

Pattern for each test file:

```bash
#!/usr/bin/env bats

load test_helper/common

setup() {
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "description of test case" {
  # Arrange: set up specific state
  # Act: call function
  # Assert: check output/return code
}
```

### Test Scenarios by File

#### `branch-freshness.bats` (spec 8.2 — Branch Freshness)

Tests for `get_branch_tracking_status()` from `git-utils.sh`:

- `@test "branch behind remote — auto fast-forward succeeds"` — Push a commit to remote from another clone, verify fast-forward.
- `@test "branch behind remote — fast-forward fails with merge commit"` — Create diverged state where ff is not possible, verify warning.
- `@test "branch diverged from remote — warning with options"` — Create diverged commits on both sides, verify "diverged" status.
- `@test "branch ahead of remote — unpushed info"` — Create local commit not pushed, verify "ahead" status.
- `@test "no remote — no freshness check"` — Remove remote, verify no error and appropriate skip.
- `@test "fetch fails — warning emitted, continues"` — Use invalid remote URL, verify warning and continuation.

#### `drift-detection.bats` (spec 8.2 — Base Branch Drift)

Tests for `get_base_branch_drift()` from `rebase.sh`:

- `@test "base branch has drifted — rebase attempted"` — Push new commits to base on remote, verify drift detected.
- `@test "base branch has not drifted — no action"` — No new base commits, verify no drift.
- `@test "no common ancestor — warning emitted, push proceeds"` — Orphan branches, verify warning.

#### `rebase.bats` (spec 8.2 — Rebase and Conflicts)

Tests for `attempt_rebase()`, `get_conflict_details()`, `needs_force_push()` from `rebase.sh`:

- `@test "clean rebase succeeds — success message"` — Non-conflicting rebase completes.
- `@test "rebase with conflicts — conflict details reported"` — Conflicting changes, verify JSON conflict details output.
- `@test "conflict strategy abort — rebase aborted immediately"` — Config set to `"abort"`, verify rebase is aborted.
- `@test "conflict strategy merge-fallback — merge attempted after rebase fails"` — Config set to `"merge-fallback"`, verify merge attempt.
- `@test "force push detection after rebase — prompt based on config"` — Verify `needs_force_push()` returns true after rebase.
- `@test "push rejection detected — options presented"` — Simulate push rejection scenario.

#### `agent-detection.bats` (spec 8.2 — Agent Detection)

Tests for `is_agent_context()` and `is_operation_agent_restricted()` from `agent.sh`:

- `@test "CLAUDE_SPAWNED_BY set — is_agent_context returns true"` — Set env var, verify detection.
- `@test "state file isAgent true — is_agent_context returns true"` — Write state with `isAgent: true`, verify detection.
- `@test "neither set — normal interactive behavior"` — No env var, no state flag, verify returns false.
- `@test "push operation restricted for agents"` — Verify `is_operation_agent_restricted "push"` returns true in agent context.

#### `worktree.bats` (spec 8.2 — Worktree Management)

Tests for `create_worktree()`, `remove_worktree()`, `list_worktrees()`, `merge_worktree_branch()` from `worktree.sh`:

- `@test "worktree created — registered in registry"` — Create worktree, verify `.git/git-pilot-worktrees.json` entry.
- `@test "worktree removed — unregistered from registry"` — Remove worktree, verify registry entry gone.
- `@test "worktree merge — branch merged, worktree cleaned up"` — Merge worktree branch, verify merge and cleanup.
- `@test "worktree directory already exists — error reported"` — Pre-create the directory, verify error.

#### `stash.bats` (spec 8.2 — Stash Management)

Tests for `auto_stash()` and `auto_restore_stash()` from `git-utils.sh`:

- `@test "auto-stash on branch switch — changes stashed, message emitted"` — Make changes, call auto_stash, verify stash created.
- `@test "auto-restore on return — stash popped, message emitted"` — Stash changes, switch and return, call auto_restore, verify restored.
- `@test "restore fails — warning with manual instructions"` — Create conflict scenario for stash pop, verify warning.

#### `protected-branch.bats` (spec 8.2 — Protected Branch)

Tests for `normalize_protect_default_branch()` and protected branch enforcement in `pre-commit.sh`:

- `@test "warn mode — warning emitted, commit allowed"` — Config `"warn"`, verify warning output and exit 0.
- `@test "block mode — commit blocked with exit code 2"` — Config `"block"`, verify exit code 2.
- `@test "off mode — no message"` — Config `"off"`, verify no output.
- `@test "boolean true — treated as warn"` — Config `true`, verify same as `"warn"`.
- `@test "boolean false — treated as off"` — Config `false`, verify same as `"off"`.

#### `config-compat.bats` (spec 8.2 — Config Backward Compatibility)

Tests for config normalization and merge logic in `config.sh`:

- `@test "v1 config protectDefaultBranch true — normalized to warn"` — Write v1 config, verify normalization.
- `@test "v1 config protectDefaultBranch false — normalized to off"` — Write v1 config, verify normalization.
- `@test "v2 config with all new keys — works as specified"` — Write full v2 config, verify all keys accessible.
- `@test "missing new keys — defaults used"` — Write minimal config, verify defaults fill in.

### General Testing Patterns

Each test should:
1. Create a temporary git repository with controlled state in `setup()`.
2. Source the script under test with appropriate `SCRIPT_DIR` and config paths set.
3. Call the function directly and capture output/return code.
4. Use `[ "$status" -eq 0 ]` and `[[ "$output" == *"expected"* ]]` for assertions.
5. Clean up in `teardown()`.

Avoid testing hook scripts end-to-end (those require the Claude Code runtime). Focus on testing the library functions that hooks call.

## Files to Create or Modify
- plugins/git-pilot/tests/test_helper/common.bash (new)
- plugins/git-pilot/tests/branch-freshness.bats (new)
- plugins/git-pilot/tests/drift-detection.bats (new)
- plugins/git-pilot/tests/rebase.bats (new)
- plugins/git-pilot/tests/agent-detection.bats (new)
- plugins/git-pilot/tests/worktree.bats (new)
- plugins/git-pilot/tests/stash.bats (new)
- plugins/git-pilot/tests/protected-branch.bats (new)
- plugins/git-pilot/tests/config-compat.bats (new)

## Validation Notes

### PASSED: Test file names match the spec-required names

All 8 required test files now exist with the correct names. `state.bats` remains as a bonus file.

### Criteria Status

- [x] `plugins/git-pilot/tests/test_helper/common.bash` exists with shared setup/teardown fixtures that create temporary git repos with controlled state.
- [x] All 8 test files exist: `branch-freshness.bats`, `drift-detection.bats`, `rebase.bats`, `agent-detection.bats`, `worktree.bats`, `stash.bats`, `protected-branch.bats`, `config-compat.bats`.
- [x] Each `.bats` file sources the appropriate script under test and the shared helper.
- [x] Each test scenario from spec section 8.2 has a corresponding `@test` block.
- [x] All tests can be run with `bats plugins/git-pilot/tests/` (assuming bats-core is installed).
- [x] Tests use temporary directories (cleaned up in teardown) and do not modify the real repository.
