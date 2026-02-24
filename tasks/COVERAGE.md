# Task Coverage Validation Report

Generated: 2026-02-24

---

## Check 1: Spec Coverage

For each spec module (01-07), every requirement (function, config key, error message, behavior) was checked against task acceptance criteria.

### Spec 01: Config and State (`spec/01-config-and-state.md`)

| Requirement | Covered by Task(s) |
|---|---|
| Three-tier config merge (`load_config`, `get_config`) unchanged | 001 (AC3) |
| Config file locations (defaults, global, local) | 001 (AC1) |
| Complete v2 `defaults/config.json` schema | 001 (AC1) |
| `normalize_protect_default_branch()` function | 001 (AC2), 007 (AC7) |
| Backward compatibility: boolean-to-string migration | 001 (AC4), 009 (AC4-AC7) |
| `init_state()` 5-argument signature | 002 (AC1) |
| v2 session state fields (baseBranch, branchPurpose, lastFetchAt, isAgent, agentRole, activeWorktrees, stashRefs) | 002 (AC2) |
| `update_state()` variadic jq arguments | 002 (AC3) |
| `read_state()` returns `{}` on missing/invalid JSON | 002 (AC4) |
| Atomic write pattern (`write_state`) | 002 (AC6 -- unchanged) |
| `cleanup_state()` unchanged | 002 (AC6) |
| Worktree registry schema (`git-pilot-worktrees.json`) | 006 (AC1-AC6) |
| Protected branch behavior by mode (warn/block/off) | 009 (AC4-AC7) |
| Error: config parse failure message | 001 (AC4 -- three-tier merge guards) |
| Error: state file failure message | 002 (AC4 -- read_state guard) |
| Error: missing git/jq warnings | 008 (session-start checks) |
| Version bump 1.1.0 -> 2.0.0 | 018 (AC1) |

**Result: All requirements covered.**

### Spec 02: Git Utilities and Network (`spec/02-git-utils-and-network.md`)

| Requirement | Covered by Task(s) |
|---|---|
| `get_branch_tracking_status()` function and all 5 return values | 003 (AC1) |
| `fetch_with_retry()` with configurable retries and delay | 003 (AC2) |
| Silent retries; last_error on stderr on failure | 003 (AC6) |
| `derive_branch_purpose()` function | 003 (AC3) |
| Core v1 utility functions unchanged | 003 (AC5) |
| Branch freshness systemMessages (behind, ahead, diverged, up-to-date, no-remote) | 008 (AC2) |
| Fast-forward auto-merge on `behind:N` | 008 (AC2) |
| Network error messages (all retries exhausted, push failed) | 008 (AC1), 010 (AC3-AC4) |
| Integration: fetch before freshness check in session-start | 008 (AC1) |
| `lastFetchAt` updated on successful fetch | 008 (AC1, via state) |
| Edge cases: autoFetch false, no remote, no tracking branch | 008 (AC6) |

**Result: All requirements covered.**

### Spec 03: Rebase and Conflicts (`spec/03-rebase-and-conflicts.md`)

| Requirement | Covered by Task(s) |
|---|---|
| `get_base_branch_drift()` function with 3 return values | 005 (AC2) |
| Base branch determination order (state, git config, default) | 005 (notes), 012 (AC2), 015 (AC3) |
| `attempt_rebase()` function with 4 return values | 005 (AC3) |
| `get_conflict_details()` JSON output | 005 (AC4) |
| Conflict type detection (both-modified, deleted-by-us, deleted-by-them) | 005 (AC4) |
| Conflict recommendation heuristics | 005 (AC7) |
| `rebase.conflictStrategy` handling (prompt/abort/merge-fallback) | 005 (AC6 reference), 012 (AC3) |
| `needs_force_push()` function | 005 (AC5) |
| `rebase.allowForcePush` handling (ask/never/always) | 005 (notes) |
| Force push uses `--force-with-lease` only | 005 (notes) |
| Push rejection detection and 4-option message | 010 (AC2-AC4) |
| Conflict resolution systemMessage format | 012 (AC3) |
| Drift detection in session-stop.sh | 012 (AC2) |

**Result: All requirements covered.**

### Spec 04: Agent Teams Detection and Worktree Management (`spec/04-agent-and-worktree.md`)

| Requirement | Covered by Task(s) |
|---|---|
| `is_agent_context()` -- CLAUDE_SPAWNED_BY detection | 004 (AC2) |
| `is_agent_context()` -- state file isAgent fallback | 004 (AC3) |
| `is_agent_context()` -- returns 1 when neither | 004 (AC4) |
| `is_operation_agent_restricted()` function | 004 (AC5-AC6) |
| Prompt suppression pattern in hooks | 010 (AC1), 011 (AC3), 013 (AC3) |
| Agent suppression in session-start (freshness to state only) | 008 (not explicitly covered -- see note below) |
| Agent suppression in session-stop (rebase/summary) | 012 (AC4) |
| Operations and agent behavior table | 004 (notes), 010, 011, 012, 013 |
| CLAUDE.md Rule 10 (Agent Teams) | 017 (AC5) |
| `create_worktree()` function | 006 (AC2-AC3) |
| `remove_worktree()` function | 006 (AC4) |
| `list_worktrees()` function | 006 (AC5) |
| `merge_worktree_branch()` function | 006 (AC6) |
| Worktree registry (register/unregister) | 006 (AC2, AC4) |
| `{{project}}` placeholder replacement | 006 (AC2) |
| Worktree cleanup in session-stop | 012 (AC5) |
| Invariants: half-created worktree cleanup | 006 (notes) |
| Config keys: agentTeams.suppressPromptsForAgents, orchestratorOnly | 004 (AC7), 001 (AC1) |
| Config keys: worktree.enabled, basePath, cleanupOnMerge | 006 (AC7), 001 (AC1) |

**Note -- Agent suppression in session-start.sh**: Spec 04 section 1.5 specifies that agents should still fetch and fast-forward but log freshness to state only (no systemMessage prompt). Task 008 does not have an explicit acceptance criterion for agent suppression in session-start.sh. However, task 008's scope states "add four new capabilities" and the spec code it references (spec/06 section 3b) includes the agent context handling. This is a **minor gap** -- it is implicitly covered by the spec code references but not explicitly stated as an acceptance criterion.

**Result: 1 minor gap found (agent suppression in session-start not explicit in task 008 AC). All other requirements covered.**

### Spec 05: Stash Management, Detached HEAD Recovery, and Protected Branch Enhancement (`spec/05-stash-and-robustness.md`)

| Requirement | Covered by Task(s) |
|---|---|
| `auto_stash()` function | 007 (AC1-AC2) |
| `auto_restore_stash()` function | 007 (AC3-AC5) |
| Stash message format | 007 (AC2) |
| Stash state tracking (stashRefs array) | 007 (AC2, AC4) |
| Branch switch detection (`is_branch_switch_command()`) | 009 (AC1) |
| Auto-stash on branch switch trigger in pre-commit.sh | 009 (AC2-AC3) |
| CLAUDE.md Rule 8 (Branch switching) | 017 (AC3) |
| Stash data never lost invariant | 007 (AC6) |
| Detached HEAD detection and recovery | 008 (AC3) |
| Protected branch tri-state (warn/block/off) | 009 (AC4-AC7) |
| `normalize_protect_default_branch()` backward compat | 001 (AC2), 007 (AC7) |
| `output_block()` for block mode | 009 (AC5) |
| `output_allow_with_message()` for stash | 009 (AC2) |
| Hook output helper functions | 009 (pre-commit already has them in v1) |
| Error handling invariants (never leave broken state) | 007 (AC6), 005 (notes) |
| Stash messages (auto-stash, auto-restore, restore failed) | 007 (AC2), 009 (AC2) |

**Result: All requirements covered.**

### Spec 06: Hooks and Lifecycle (`spec/06-hooks-and-lifecycle.md`)

| Requirement | Covered by Task(s) |
|---|---|
| Updated hooks.json (timeouts, new UserPromptSubmit entry) | 014 (AC1-AC7) |
| `prompt-context.sh` new script | 013 (AC1-AC7) |
| session-start.sh: fetch remote (3a) | 008 (AC1) |
| session-start.sh: branch freshness (3b) | 008 (AC2) |
| session-start.sh: detached HEAD (3c) | 008 (AC3) |
| session-start.sh: extended state init (3d) | 008 (AC4-AC5) |
| session-stop.sh: drift detection (4a) | 012 (AC2-AC3) |
| session-stop.sh: worktree cleanup (4b) | 012 (AC5) |
| session-stop.sh: agent suppression | 012 (AC4) |
| post-bash.sh: agent suppression (5a) | 010 (AC1) |
| post-bash.sh: push rejection detection (5b) | 010 (AC2-AC4) |
| post-write.sh: agent suppression | 011 (AC1-AC5) |
| pre-commit.sh: branch switch with auto-stash (7a) | 009 (AC1-AC3) |
| pre-commit.sh: enhanced protected branch blocking (7b) | 009 (AC4-AC7) |

**Result: All requirements covered.**

### Spec 07: Skills and CLAUDE.md (`spec/07-skills-and-claude-md.md`)

| Requirement | Covered by Task(s) |
|---|---|
| Complete v2 CLAUDE.md with 10 rules | 017 (AC1-AC6) |
| Rule 7: Unrelated work detection | 017 (AC2) |
| Rule 8: Branch switching | 017 (AC3) |
| Rule 9: Conflict resolution | 017 (AC4) |
| Rule 10: Agent Teams | 017 (AC5) |
| Skill reference table (7 skills) | 017 (AC6) |
| `/branch` skill modification (Step 5) | 015 (AC1) |
| `/finish` skill modification (Step 1.5) | 015 (AC2-AC3) |
| `/summary` skill -- no changes needed | 015 (noted in spec 3.3) |
| `/configure` skill -- new reference entries | 015 (AC4) |
| `/stash` skill (new) | 016 (AC1) |
| `/worktree` skill (new) | 016 (AC2) |
| `/rebase` skill (new) | 016 (AC3) |
| Config keys reference (11 keys in section 5) | 001 (AC1) |

**Result: All requirements covered.**

### Check 1 Summary

**1 minor gap found**: Task 008 (hook-session-start) does not have an explicit acceptance criterion for agent suppression of freshness messages in session-start.sh, as specified in spec/04 section 1.5. The behavior is referenced in the spec code that task 008 implements, so it is implicitly covered, but it should ideally be an explicit AC.

---

## Check 2: Valid DAG

### Dependency Graph (Text Format)

```
001-config-schema (no deps)
  |
  +---> 002-state-schema
  |       |
  |       +---> 004-agent-library (also depends on 001)
  |       |       |
  |       |       +---> 010-hook-post-bash
  |       |       +---> 011-hook-post-write
  |       |       +---> 012-hook-session-stop (also depends on 003, 005, 006)
  |       |       +---> 013-hook-prompt-context (also depends on 003)
  |       |       +---> 017-claude-md-update (also depends on 005, 006, 007)
  |       |
  |       +---> 007-stash-functions
  |       |       |
  |       |       +---> 009-hook-pre-commit (also depends on 001)
  |       |       +---> 016-skills-new (also depends on 005, 006)
  |       |       +---> 017-claude-md-update (also depends on 004, 005, 006)
  |       |
  |       +---> 008-hook-session-start (also depends on 001, 003)
  |
  +---> 003-git-utils-extensions
  |       |
  |       +---> 005-rebase-library (also depends on 001)
  |       |       |
  |       |       +---> 012-hook-session-stop (also depends on 004, 006)
  |       |       +---> 015-skills-modified (also depends on 001)
  |       |       +---> 016-skills-new (also depends on 006, 007)
  |       |       +---> 017-claude-md-update (also depends on 004, 006, 007)
  |       |
  |       +---> 008-hook-session-start (also depends on 001, 002)
  |       +---> 012-hook-session-stop (also depends on 004, 005, 006)
  |       +---> 013-hook-prompt-context (also depends on 004)
  |
  +---> 006-worktree-library
  |       |
  |       +---> 012-hook-session-stop (also depends on 003, 004, 005)
  |       +---> 016-skills-new (also depends on 005, 007)
  |       +---> 017-claude-md-update (also depends on 004, 005, 007)
  |
  +---> 009-hook-pre-commit (also depends on 007)
  +---> 015-skills-modified (also depends on 005)

014-hook-registration
  +---> depends on 013-hook-prompt-context

018-plugin-metadata
  +---> depends on 017-claude-md-update

019-test-suite
  +---> depends on ALL tasks 001-018
```

### Full Dependency List per Task

| Task | Dependencies |
|---|---|
| 001-config-schema | (none) |
| 002-state-schema | 001 |
| 003-git-utils-extensions | 001 |
| 004-agent-library | 001, 002 |
| 005-rebase-library | 001, 003 |
| 006-worktree-library | 001 |
| 007-stash-functions | 002 |
| 008-hook-session-start | 001, 002, 003 |
| 009-hook-pre-commit | 001, 007 |
| 010-hook-post-bash | 004 |
| 011-hook-post-write | 004 |
| 012-hook-session-stop | 003, 004, 005, 006 |
| 013-hook-prompt-context | 003, 004 |
| 014-hook-registration | 013 |
| 015-skills-modified | 001, 005 |
| 016-skills-new | 005, 006, 007 |
| 017-claude-md-update | 004, 005, 006, 007 |
| 018-plugin-metadata | 017 |
| 019-test-suite | 001-018 (all) |

### Cycle Detection

No cycles detected. The graph is a DAG. All edges point forward (lower-numbered tasks to higher-numbered tasks, with the exception of cross-references among mid-range tasks, none of which form cycles).

Verified by tracing all dependency chains:
- 001 -> 002 -> 004 -> 010 (no back-edge)
- 001 -> 002 -> 007 -> 009 (no back-edge)
- 001 -> 003 -> 005 -> 012 (no back-edge)
- 001 -> 006 -> 012 (no back-edge)
- All terminal tasks (014, 015, 016, 017, 018, 019) only depend on earlier tasks.

### Dependency Existence Verification

All dependency references match existing task file slugs:

| Referenced Dependency | File Exists? |
|---|---|
| 001-config-schema | YES |
| 002-state-schema | YES |
| 003-git-utils-extensions | YES |
| 004-agent-library | YES |
| 005-rebase-library | YES |
| 006-worktree-library | YES |
| 007-stash-functions | YES |
| 008-hook-session-start | YES |
| 009-hook-pre-commit | YES |
| 010-hook-post-bash | YES |
| 011-hook-post-write | YES |
| 012-hook-session-stop | YES |
| 013-hook-prompt-context | YES |
| 014-hook-registration | YES |
| 015-skills-modified | YES |
| 016-skills-new | YES |
| 017-claude-md-update | YES |
| 018-plugin-metadata | YES |

**Result: PASS. No cycles. All referenced dependencies exist. All slugs are correct.**

---

## Check 3: Sizing Limits

### Files to Create or Modify (max 3-4 source files)

| Task | File Count | Files | Violation? |
|---|---|---|---|
| 001-config-schema | 2 | config.json, config.sh | NO |
| 002-state-schema | 1 | state.sh | NO |
| 003-git-utils-extensions | 1 | git-utils.sh | NO |
| 004-agent-library | 2 | agent.sh (new), config.json | NO |
| 005-rebase-library | 2 | rebase.sh (new), config.json | NO |
| 006-worktree-library | 2 | worktree.sh (new), config.json | NO |
| 007-stash-functions | 1 | git-utils.sh | NO |
| 008-hook-session-start | 1 | session-start.sh | NO |
| 009-hook-pre-commit | 1 | pre-commit.sh | NO |
| 010-hook-post-bash | 1 | post-bash.sh | NO |
| 011-hook-post-write | 1 | post-write.sh | NO |
| 012-hook-session-stop | 1 | session-stop.sh | NO |
| 013-hook-prompt-context | 1 | prompt-context.sh (new) | NO |
| 014-hook-registration | 1 | hooks.json | NO |
| 015-skills-modified | 3 | branch/SKILL.md, finish/SKILL.md, configure/SKILL.md | NO |
| 016-skills-new | 3 | stash/SKILL.md (new), worktree/SKILL.md (new), rebase/SKILL.md (new) | NO |
| 017-claude-md-update | 1 | CLAUDE.md | NO |
| 018-plugin-metadata | 1 | plugin.json | NO |
| 019-test-suite | 9 | common.bash, 8 .bats files | **YES** |

### Acceptance Criteria Count (max 7)

| Task | AC Count | Violation? |
|---|---|---|
| 001-config-schema | 5 | NO |
| 002-state-schema | 6 | NO |
| 003-git-utils-extensions | 6 | NO |
| 004-agent-library | 7 | NO |
| 005-rebase-library | 7 | NO |
| 006-worktree-library | 7 | NO |
| 007-stash-functions | 7 | NO |
| 008-hook-session-start | 6 | NO |
| 009-hook-pre-commit | 7 | NO |
| 010-hook-post-bash | 6 | NO |
| 011-hook-post-write | 5 | NO |
| 012-hook-session-stop | 7 | NO |
| 013-hook-prompt-context | 7 | NO |
| 014-hook-registration | 7 | NO |
| 015-skills-modified | 6 | NO |
| 016-skills-new | 6 | NO |
| 017-claude-md-update | 6 | NO |
| 018-plugin-metadata | 5 | NO |
| 019-test-suite | 6 | NO |

### Violations

1. **Task 019 (test-suite)**: 9 files to create (1 helper + 8 test files). This exceeds the 3-4 file maximum. However, these are all test files and follow a consistent pattern, so this is an expected and justifiable exception for a comprehensive test suite task. The task could be split into 2-3 smaller test tasks if strict adherence is required.

**Result: 1 violation (task 019 file count). All acceptance criteria counts are within limits.**

---

## Check 4: File Conflicts

### Method

Two tasks conflict if they both list the same file in "Files to Create or Modify" AND they are independent (no direct or transitive dependency relationship between them).

### File-to-Task Mapping

| File | Tasks |
|---|---|
| `defaults/config.json` | 001, 004, 005, 006 |
| `scripts/config.sh` | 001 |
| `scripts/state.sh` | 002 |
| `scripts/git-utils.sh` | 003, 007 |
| `scripts/agent.sh` | 004 |
| `scripts/rebase.sh` | 005 |
| `scripts/worktree.sh` | 006 |
| `scripts/session-start.sh` | 008 |
| `scripts/pre-commit.sh` | 009 |
| `scripts/post-bash.sh` | 010 |
| `scripts/post-write.sh` | 011 |
| `scripts/session-stop.sh` | 012 |
| `scripts/prompt-context.sh` | 013 |
| `hooks/hooks.json` | 014 |
| `skills/branch/SKILL.md` | 015 |
| `skills/finish/SKILL.md` | 015 |
| `skills/configure/SKILL.md` | 015 |
| `skills/stash/SKILL.md` | 016 |
| `skills/worktree/SKILL.md` | 016 |
| `skills/rebase/SKILL.md` | 016 |
| `CLAUDE.md` | 017 |
| `.claude-plugin/plugin.json` | 018 |
| `tests/*` | 019 |

### Shared Files Analysis

**`defaults/config.json`** -- Tasks 001, 004, 005, 006:
- 004 depends on 001: OK (transitive)
- 005 depends on 001: OK (transitive)
- 006 depends on 001: OK (transitive)
- 004 vs 005: 004 depends on 001, 002. 005 depends on 001, 003. No direct or transitive dependency between 004 and 005. **POTENTIAL CONFLICT.**
- 004 vs 006: 004 depends on 001, 002. 006 depends on 001. No direct or transitive dependency between 004 and 006. **POTENTIAL CONFLICT.**
- 005 vs 006: 005 depends on 001, 003. 006 depends on 001. No direct or transitive dependency between 005 and 006. **POTENTIAL CONFLICT.**

However, examining the task details:
- Task 001 adds the COMPLETE v2 `defaults/config.json` including all sections (rebase, worktree, agentTeams).
- Tasks 004, 005, 006 each mention adding their respective config blocks to `defaults/config.json`.
- Since task 001 already writes the complete schema, tasks 004, 005, 006 listing `defaults/config.json` is redundant -- their config keys are already present from task 001. This is a documentation inconsistency rather than a true conflict: if tasks 004, 005, 006 are implemented after 001 (which they depend on), the config.json changes are already done.

**Verdict**: These are **logical conflicts** that need resolution. Tasks 004, 005, and 006 should either (a) remove `defaults/config.json` from their file lists since task 001 already writes the complete schema, or (b) be explicitly ordered relative to each other. Since they all depend on 001 which writes the complete file, the safest resolution is to remove `defaults/config.json` from tasks 004, 005, 006.

**`scripts/git-utils.sh`** -- Tasks 003, 007:
- 007 depends on 002. 003 depends on 001. No direct dependency between 003 and 007.
- Checking transitive: 007 -> 002 -> 001. 003 -> 001. They share 001 as ancestor but no dependency path exists from 003 to 007 or vice versa. **POTENTIAL CONFLICT.**

Examining the task details:
- Task 003 adds `get_branch_tracking_status()`, `fetch_with_retry()`, `derive_branch_purpose()`, `is_detached_head()`.
- Task 007 adds `auto_stash()`, `auto_restore_stash()`, `normalize_protect_default_branch()`.
- These are different functions appended to the same file, so in practice they can be applied independently. But since they are truly independent tasks modifying the same file, this is a **valid conflict**.

**Verdict**: Task 007 should depend on 003, or vice versa, to ensure ordered writes to `git-utils.sh`.

### Conflicts Found

| File | Conflicting Tasks | Severity | Recommendation |
|---|---|---|---|
| `defaults/config.json` | 004 vs 005, 004 vs 006, 005 vs 006 | LOW | Remove `defaults/config.json` from tasks 004, 005, 006 since task 001 already writes the complete v2 schema. The config keys are already present. |
| `scripts/git-utils.sh` | 003 vs 007 | MEDIUM | Add dependency: 007 should depend on 003 (or 003 on 007) to serialize writes to `git-utils.sh`. Since task 009 already depends on both 001 and 007, and task 008 depends on 003, adding 003 as a dependency of 007 is the natural choice. |

**Result: 2 conflict groups found (4 pairwise conflicts on config.json, 1 on git-utils.sh).**

---

## Summary

| Check | Result | Issues |
|---|---|---|
| 1. Spec Coverage | **PASS** (with 1 minor note) | Task 008 missing explicit AC for agent suppression of freshness messages in session-start.sh |
| 2. Valid DAG | **PASS** | No cycles, all dependencies exist, all slugs correct |
| 3. Sizing Limits | **PASS** (with 1 exception) | Task 019 has 9 files (test suite -- justifiable exception) |
| 4. File Conflicts | **FAIL** | 2 conflict groups: `defaults/config.json` (tasks 004/005/006 are independent but share file) and `scripts/git-utils.sh` (tasks 003/007 are independent but share file) |

### Overall Verdict: **FAIL -- 2 issues require resolution before proceeding**

#### Required Fixes

1. **File conflict on `defaults/config.json`**: Remove `defaults/config.json` from the "Files to Create or Modify" lists of tasks 004, 005, and 006. Task 001 already writes the complete v2 config schema including all agentTeams, rebase, and worktree sections. The acceptance criteria mentioning "added to defaults/config.json" in tasks 004 (AC7), 005 (AC6), and 006 (AC7) should be changed to "present in defaults/config.json (written by task 001)".

2. **File conflict on `scripts/git-utils.sh`**: Add `003-git-utils-extensions` as a dependency of task `007-stash-functions`. Both tasks append new functions to `git-utils.sh` and must be serialized. Since task 007 already depends on 002 (which depends on 001, same as 003), adding 003 introduces no cycle: 007 -> 003 -> 001.

#### Advisory (Non-Blocking)

3. **Task 008 agent suppression**: Consider adding an explicit acceptance criterion to task 008 for agent context handling in session-start.sh (freshness messages logged to state only, not emitted as systemMessages, per spec/04 section 1.5).

4. **Task 019 file count**: The test suite task has 9 files. Consider splitting into 2-3 test tasks (e.g., unit tests vs integration tests) if strict adherence to the 3-4 file limit is required.
