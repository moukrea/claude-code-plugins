# git-pilot v2 — Full Implementation from Technical Spec

Use delegate mode (Shift+Tab) now. You are the team lead and orchestrator — you
coordinate, you do not implement. All spec reading, task creation, coding, and
validation is done by teammates you spawn via agent teams.

The goal: implement the entire `git-pilot v2` project as defined in
`TECHNICAL-SPEC.md`, producing a fully functional Claude Code plugin directory
at `plugins/git-pilot/` with updated Bash scripts, new library scripts, updated
and new Markdown skills, updated configuration, and a bats test suite.

Work proceeds in three sequential phases. Create one agent team per phase, shut
it down and clean it up before starting the next.

---

## Phase 1: Spec Decomposition

<phase_1>

### Objective

Break `TECHNICAL-SPEC.md` into self-contained module documents sized for a
single agent's context window. This is a context engineering step — each document
must contain everything an implementing agent needs for that module without
requiring the full 2,056-line spec.

### Team Setup

Create a team. Spawn 5 teammates. Each teammate handles 2-3 spec sections.

In each spawn prompt, tell the teammate:
- The exact section numbers and line ranges of `TECHNICAL-SPEC.md` they are
  responsible for.
- The output file path(s) they should write to.
- The formatting rules below.

### Output

Create a `spec/` directory with these files:

| File | Spec Sections | Description |
|------|---------------|-------------|
| `spec/01-config-and-state.md` | §3 Data Model, §7 Configuration | Complete v2 config schema with all keys, types, and defaults. Session state schema. Worktree registry schema. Three-tier config merge logic. Backward compatibility for `protectDefaultBranch` boolean→string migration. `normalize_protect_default_branch()` function. |
| `spec/02-git-utils-and-network.md` | §4.1 Branch Freshness Detection, §4.10 Network Error Handling | `get_branch_tracking_status()` function with all return values. `fetch_with_retry()` function with retry logic and config keys. Fast-forward auto-merge logic. All freshness-related systemMessages (behind, diverged, ahead, no-remote). |
| `spec/03-rebase-and-conflicts.md` | §4.2 Base Branch Drift Detection, §4.3 Intelligent Rebase and Conflict Resolution | `get_base_branch_drift()` function. `attempt_rebase()` function. `get_conflict_details()` JSON output format. Conflict recommendation heuristics. `rebase.conflictStrategy` handling (prompt, abort, merge-fallback). `needs_force_push()` function. `rebase.allowForcePush` handling. Push rejection detection and messages. |
| `spec/04-agent-and-worktree.md` | §4.5 Agent Teams Detection, §4.6 Git Worktree Management | `is_agent_context()` detection via `CLAUDE_SPAWNED_BY` env var and state file. `is_operation_agent_restricted()` function. Prompt suppression table. `create_worktree()`, `remove_worktree()`, `list_worktrees()`, `merge_worktree_branch()` functions. Worktree registry CRUD. `worktree.basePath` template expansion. |
| `spec/05-stash-and-robustness.md` | §4.7 Stash Management, §4.8 Detached HEAD Recovery, §4.9 Protected Branch Enhancement | `auto_stash()` and `auto_restore_stash()` functions with state tracking. Stash ref recording in session state. Detached HEAD detection via empty `get_current_branch()` + reflog lookup. `protectDefaultBranch` "warn"/"block"/"off" enforcement in `pre-commit.sh`. |
| `spec/06-hooks-and-lifecycle.md` | §5.1 Hook Scripts (all subsections) | Updated `hooks.json` with new timeouts and `UserPromptSubmit` hook. Complete `prompt-context.sh` script. All modifications to `session-start.sh` (fetch, freshness, detached HEAD, extended state init). All modifications to `session-stop.sh` (drift detection, worktree cleanup). All modifications to `post-bash.sh` (agent suppression, push rejection). All modifications to `post-write.sh` (agent suppression). All modifications to `pre-commit.sh` (branch switch detection, block mode). |
| `spec/07-skills-and-claude-md.md` | §4.4 Unrelated Work Detection, §5.2 Skills, §5.3 CLAUDE.md | Complete v2 CLAUDE.md with all 10 rules. Unrelated work detection as CLAUDE.md Rule 7 + `derive_branch_purpose()` function. Modifications to `/branch` (base branch recording), `/finish` (drift detection), `/configure` (new keys). Complete new skills: `/stash`, `/worktree`, `/rebase`. Updated skill reference table. |

### Rules for Each Module Document

1. Self-contained — include all relevant details inline. Do not write "see
   TECHNICAL-SPEC.md" or summarize. An agent reading only this file must have
   everything it needs.
2. Preserve verbatim — exact function names, variable names, config key paths,
   error messages, jq filters, bash code snippets, systemMessage strings. Copy
   from the spec, do not paraphrase technical specifics.
3. Cross-references at the top — list which other module docs this one depends on
   and why (e.g., "Depends on: `01-config-and-state.md` for config schema and
   `get_config()` function signature").
4. Under 400 lines each.

### Validation

After all module docs are written, spawn one more teammate to validate:
1. Read `TECHNICAL-SPEC.md` in full.
2. Read every `spec/*.md` file.
3. Write `spec/VALIDATION.md` listing any omissions, contradictions, or spec drift.
4. If issues exist, message you with the list. You message the responsible
   teammates to fix them.
5. The validator re-checks after fixes. Phase 1 is complete only when
   `spec/VALIDATION.md` reports zero issues.

Shut down all teammates and clean up the team before proceeding.

</phase_1>

---

## Phase 2: Task Planning

<phase_2>

### Objective

Create a set of small, independently implementable tasks with a file-based
tracking system. Do not use Claude Code's built-in task tools
(TaskCreate/TaskUpdate/TaskList) — use the directory structure described below.

### Team Setup

Create a new team. Spawn 4 teammates. Each teammate reads a subset of the
`spec/*.md` files (not the original tech spec — the decomposed modules from
Phase 1).

In each spawn prompt, tell the teammate:
- Which `spec/*.md` files to read.
- The task file template and naming convention.
- That all task files go in `tasks/todo/`.

### Output

Directory structure:

```
tasks/
├── todo/
├── in-progress/
├── to-validate/
└── done/
```

Each task is a Markdown file: `NNN-short-slug.md` (e.g., `001-project-init.md`).
All start in `todo/`.

Task file template:

```markdown
# Task NNN: Short Title

## Status
todo

## Dependencies
- NNN-short-slug (what this task needs from that one)
- (or "None")

## Spec References
- spec/XX-module.md

## Scope
One paragraph. What this task implements — one focused piece of functionality.

## Acceptance Criteria
- [ ] Criterion 1 (concrete, verifiable)
- [ ] Criterion 2
- [ ] ...

## Implementation Notes
Details the implementing agent needs: function signatures, exact error
messages, jq filters, bash patterns, config key paths. Quote the spec
module directly.

## Files to Create or Modify
- plugins/git-pilot/scripts/foo.sh (new)
- plugins/git-pilot/scripts/bar.sh (modify)
```

### Sizing Rules

- Each task: implementable by one agent in one session.
- Maximum 3-4 source files per task.
- Maximum 7 acceptance criteria. If more, split the task.
- The "Files to Create or Modify" section prevents file conflicts during parallel
  implementation — no two tasks should list the same file unless one depends on
  the other.

### Ordering

Start with foundational tasks, then build up:

1. Config schema update — `defaults/config.json` with all new keys, `normalize_protect_default_branch()` in `config.sh`
2. State schema extension — new fields in `state.sh` `init_state()`, updated `read_state()`
3. git-utils extensions — `get_branch_tracking_status()`, `fetch_with_retry()`, `derive_branch_purpose()`, `is_detached_head()` in `git-utils.sh`
4. Agent detection library — new `agent.sh` with `is_agent_context()`, `is_operation_agent_restricted()`
5. Rebase library — new `rebase.sh` with `attempt_rebase()`, `get_conflict_details()`, `needs_force_push()`, `get_base_branch_drift()`
6. Worktree library — new `worktree.sh` with `create_worktree()`, `remove_worktree()`, `list_worktrees()`, `merge_worktree_branch()`, registry CRUD
7. Stash functions — `auto_stash()`, `auto_restore_stash()` in `git-utils.sh`
8. Hook: session-start.sh modifications — fetch, freshness, detached HEAD, extended state init
9. Hook: pre-commit.sh modifications — branch switch detection, auto-stash, block mode
10. Hook: post-bash.sh modifications — agent suppression, push rejection detection
11. Hook: post-write.sh modifications — agent suppression
12. Hook: session-stop.sh modifications — drift detection, rebase, worktree cleanup
13. Hook: prompt-context.sh (new) — UserPromptSubmit branch context
14. Hook registration: hooks.json update — new timeouts, UserPromptSubmit entry
15. Skills: modified `/branch`, `/finish`, `/configure`
16. Skills: new `/stash`, `/worktree`, `/rebase`
17. CLAUDE.md update — all 10 rules, updated skill table
18. Plugin metadata — `plugin.json` version bump to 2.0.0, updated description
19. Test suite — bats tests for all new functions and scenarios

Dependencies must form a DAG. No cycles.

### Validation

Spawn a validation teammate to check:
1. Every requirement in every `spec/*.md` file is covered by at least one task's
   acceptance criteria. Write `tasks/COVERAGE.md` mapping each spec module to
   its task(s).
2. The dependency graph is a valid DAG.
3. No task exceeds the sizing limits.
4. No two independent tasks (no dependency relationship) list the same file in
   "Files to Create or Modify."

Phase 2 is complete when validation passes. Shut down and clean up the team.

</phase_2>

---

## Phase 3: Implementation

<phase_3>

### Objective

Implement all tasks. Each moves through:
`todo/` -> `in-progress/` -> `to-validate/` -> `done/`.

### Team Setup

Create a new team. Spawn teammates with clear role names:

- **Implementers** (`impl-1`, `impl-2`, `impl-3`, `impl-4`) — write code.
- **Validators** (`validator-1`, `validator-2`) — review completed work.

In each implementer's spawn prompt, include:
- Their role: pick up task files from `tasks/todo/`, read the task and its spec
  references, implement the code, then move the task to `tasks/to-validate/`.
- The working directory for code: `plugins/git-pilot/`.
- That they must run `bash -n <script>` for syntax checking and
  `shellcheck <script>` for linting before marking a task as ready for validation.
- That they must check dependency tasks are in `tasks/done/` before starting a task.
- That they must preserve all existing v1 functionality — only add to or modify
  existing code, never remove working features.
- That all bash scripts must start with `#!/usr/bin/env bash` and `set -euo pipefail`.
- That all new functions must follow the naming convention: `snake_case`.
- That all systemMessages must be prefixed with `[git-pilot]`.

In each validator's spawn prompt, include:
- Their role: pick up task files from `tasks/to-validate/`, verify acceptance
  criteria, run `bash -n` and `shellcheck` on modified scripts, and either move
  to `tasks/done/` or back to `tasks/in-progress/` with notes.
- That they must verify the implementation matches the spec modules referenced in
  the task — exact function names, error messages, config key paths, jq filters.
- That they must verify backward compatibility: v1 config files must still work.
- That they must check that `source` directives reference the correct paths.

### Implementer Workflow

1. Check `tasks/todo/` for available tasks. Pick the lowest-numbered task whose
   dependencies are all in `tasks/done/`.
2. Read the task file and all `spec/*.md` files listed in its Spec References.
3. Move the file: `mv tasks/todo/NNN-slug.md tasks/in-progress/NNN-slug.md`.
   Update the Status line to `in-progress`.
4. Write the code. Follow existing patterns in the codebase — source shared
   libraries with `source "$SCRIPT_DIR/lib.sh"`, use `get_config` for config
   access, use `jq -n` for JSON output, use atomic writes via `write_state`.
5. Run `bash -n <script>` for syntax check and `shellcheck <script>` for lint.
   Fix any errors.
6. Move the file: `mv tasks/in-progress/NNN-slug.md tasks/to-validate/NNN-slug.md`.
   Update Status to `to-validate`.
7. Message the lead that the task is ready.

### Validator Workflow

1. Check `tasks/to-validate/` for tasks to review.
2. Read the task file, its spec references, and the implemented code.
3. Verify every acceptance criterion. Check each one as `[x]` if met.
4. Run `bash -n` on all modified `.sh` files. Run `shellcheck` on all modified
   `.sh` files.
5. If all criteria pass and checks pass: move to `tasks/done/`, update Status to
   `done`, message the lead.
6. If anything fails: append a `## Validation Notes` section with specific issues
   and how to fix them. Move to `tasks/in-progress/`, update Status to
   `in-progress`, message the lead. The lead assigns it to an implementer.

### Coordination Rules

- A validator must not validate work done by the same agent that implemented it.
- Avoid file conflicts: do not assign two implementers tasks that modify the same
  files simultaneously. Use the "Files to Create or Modify" section to check for
  overlap.
- After each task reaches `done/`, check if previously blocked tasks are now
  unblocked and assign them.
- If a task fails validation, the implementer must address every point in the
  Validation Notes before resubmitting.

### Completion Criteria

The implementation is done when:
1. All task files are in `tasks/done/`.
2. `bash -n plugins/git-pilot/scripts/*.sh` succeeds for all scripts.
3. `shellcheck plugins/git-pilot/scripts/*.sh` passes with no errors (warnings acceptable).
4. The `defaults/config.json` is valid JSON: `jq . plugins/git-pilot/defaults/config.json`.
5. The `hooks/hooks.json` is valid JSON: `jq . plugins/git-pilot/hooks/hooks.json`.
6. The `plugin.json` version is `2.0.0`.
7. All new skills have valid frontmatter (name, description).
8. CLAUDE.md contains all 10 rules and the updated skill reference table.

Shut down all teammates and clean up the team.

</phase_3>

---

## Orchestrator Constraints

<constraints>
- Stay in delegate mode. Do not read spec sections, write code, or run builds yourself.
- One team at a time. Shut down all teammates and clean up each team before creating the next.
- Within each phase, maximize parallelism by assigning independent work to different teammates simultaneously. Avoid assigning tasks that touch the same files to different teammates.
- When spawning teammates, provide enough context in the spawn prompt for them to work autonomously. They do not inherit your conversation history. Include file paths, role description, and what "done" looks like.
- If a teammate encounters a genuine ambiguity in the spec (a contradiction or missing detail), they should document it in `DECISIONS.md` at the repo root with the interpretation chosen and the reasoning, then proceed.
- Implement exactly what the spec describes. Do not add features, abstractions, error handling for impossible cases, or refactoring beyond the spec.
- Do not escalate to the user. Handle all decisions autonomously within the spec's boundaries.
</constraints>
