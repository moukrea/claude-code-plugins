# Prompt Template for PROMPT.md Generation

This template defines the structure of the generated PROMPT.md file. Replace all
`{{SLOT}}` placeholders with project-specific values. Preserve the exact structure,
XML-like phase tags, and constraint block.

---

## Template

```text
# {{PROJECT_NAME}} — Full Implementation from Technical Spec

Use delegate mode (Shift+Tab) now. You are the team lead and orchestrator — you
coordinate, you do not implement. All spec reading, task creation, coding, and
validation is done by teammates you spawn via agent teams.

The goal: implement the entire `{{PROJECT_NAME}}` project as defined in
`{{SPEC_FILE_PATH}}`, producing {{OUTPUT_DESCRIPTION}}.

Work proceeds in three sequential phases. Create one agent team per phase, shut
it down and clean it up before starting the next.

---

## Phase 1: Spec Decomposition

<phase_1>

### Objective

Break `{{SPEC_FILE_PATH}}` into self-contained module documents sized for a
single agent's context window. This is a context engineering step — each document
must contain everything an implementing agent needs for that module without
requiring the full {{SPEC_LINE_COUNT}}-line spec.

### Team Setup

Create a team. Spawn {{PHASE1_TEAM_SIZE}} teammates. Each teammate handles
{{SECTIONS_PER_AGENT}} spec sections.

In each spawn prompt, tell the teammate:
- The exact section numbers and line ranges of `{{SPEC_FILE_PATH}}` they are
  responsible for.
- The output file path(s) they should write to.
- The formatting rules below.

### Output

Create a `spec/` directory with these files:

{{MODULE_DOCUMENT_TABLE}}

### Rules for Each Module Document

1. Self-contained — include all relevant details inline. Do not write "see
   {{SPEC_FILE_PATH}}" or summarize. An agent reading only this file must have
   everything it needs.
2. Preserve verbatim — exact names, types, flag names, error messages, validation
   rules, data formats, behavioral rules. Copy from the spec, do not paraphrase
   technical specifics.
3. Cross-references at the top — list which other module docs this one depends on
   and why (e.g., "Depends on: `NN-module.md` for XYZ definition").
4. Under 400 lines each.

### Validation

After all module docs are written, spawn one more teammate to validate:
1. Read `{{SPEC_FILE_PATH}}` in full.
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

Create a new team. Spawn {{PHASE2_TEAM_SIZE}} teammates. Each teammate reads a
subset of the `spec/*.md` files (not the original tech spec — the decomposed
modules from Phase 1).

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
Details the implementing agent needs: struct fields, flag names, exact error
messages, algorithm steps, library APIs to use, edge cases. Quote the spec
module directly.

## Files to Create or Modify
- src/foo.ext (new)
- src/bar.ext (modify)
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

{{BUILD_ORDER}}

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

- **Implementers** (`impl-1`, `impl-2`, ... `impl-{{PHASE3_IMPL_COUNT}}`) — write code.
- **Validators** (`validator-1`, ... `validator-{{PHASE3_VALIDATOR_COUNT}}`) — review completed work.

In each implementer's spawn prompt, include:
- Their role: pick up task files from `tasks/todo/`, read the task and its spec
  references, implement the code, then move the task to `tasks/to-validate/`.
- The working directory for code: `{{CODE_ROOT}}`.
- That they must run `{{CHECK_COMMAND}}` (and `{{TEST_COMMAND}}` if applicable)
  before marking a task as ready for validation.
- That they must check dependency tasks are in `tasks/done/` before starting a task.

In each validator's spawn prompt, include:
- Their role: pick up task files from `tasks/to-validate/`, verify acceptance
  criteria, run `{{LINT_COMMAND}}` and `{{TEST_COMMAND}}`, and either move to
  `tasks/done/` or back to `tasks/in-progress/` with notes.
- That they must verify the implementation matches the spec modules referenced in
  the task — exact flag names, error messages, data formats, behavioral rules.

### Implementer Workflow

1. Check `tasks/todo/` for available tasks. Pick the lowest-numbered task whose
   dependencies are all in `tasks/done/`.
2. Read the task file and all `spec/*.md` files listed in its Spec References.
3. Move the file: `mv tasks/todo/NNN-slug.md tasks/in-progress/NNN-slug.md`.
   Update the Status line to `in-progress`.
4. Write the code. Follow existing patterns in the codebase.
5. Run `{{CHECK_COMMAND}}` and `{{TEST_COMMAND}}`. Fix any errors or test failures.
6. Move the file: `mv tasks/in-progress/NNN-slug.md tasks/to-validate/NNN-slug.md`.
   Update Status to `to-validate`.
7. Message the lead that the task is ready.

### Validator Workflow

1. Check `tasks/to-validate/` for tasks to review.
2. Read the task file, its spec references, and the implemented code.
3. Verify every acceptance criterion. Check each one as `[x]` if met.
4. Run `{{LINT_COMMAND}}` and `{{TEST_COMMAND}}` on the full project.
5. If all criteria pass and tests pass: move to `tasks/done/`, update Status to
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
{{COMPLETION_CRITERIA}}

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
```

## Slot Reference

| Slot | Source | Example |
|------|--------|---------|
| `{{PROJECT_NAME}}` | Spec title or user input | `opaq` |
| `{{SPEC_FILE_PATH}}` | Path to the spec file | `TECHNICAL-SPEC.md` |
| `{{SPEC_LINE_COUNT}}` | `wc -l` on spec file | `1237` |
| `{{OUTPUT_DESCRIPTION}}` | What the project produces | `a compilable Rust binary and a complete Claude Code plugin directory` |
| `{{PHASE1_TEAM_SIZE}}` | Team sizing table | `4-5` |
| `{{SECTIONS_PER_AGENT}}` | Total sections / team size | `3-4` |
| `{{MODULE_DOCUMENT_TABLE}}` | Module mapping from Step 3 | Markdown table of files and sections |
| `{{PHASE2_TEAM_SIZE}}` | Team sizing table | `3-4` |
| `{{BUILD_ORDER}}` | Numbered list from Step 4 | Project-specific build sequence |
| `{{PHASE3_IMPL_COUNT}}` | Team sizing table | `3` |
| `{{PHASE3_VALIDATOR_COUNT}}` | Team sizing table | `2` |
| `{{CODE_ROOT}}` | Where source code lives | `src/` or project root |
| `{{CHECK_COMMAND}}` | Quick compilation check | `cargo check`, `npm run build`, `go build ./...` |
| `{{TEST_COMMAND}}` | Test suite command | `cargo test`, `npm test`, `go test ./...` |
| `{{LINT_COMMAND}}` | Linter command | `cargo clippy -- -D warnings`, `eslint .`, `golangci-lint run` |
| `{{COMPLETION_CRITERIA}}` | Numbered list of done conditions | Project-specific success criteria |
