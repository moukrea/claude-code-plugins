# Example: Generated PROMPT.md for a Rust CLI Project

This is an example of a generated PROMPT.md for a medium-complexity Rust CLI
application (~1200 line spec, 15 module documents, ~25 tasks). Use this as
a reference for structure, tone, and level of detail.

---

# example-tool — Full Implementation from Technical Spec

Use delegate mode (Shift+Tab) now. You are the team lead and orchestrator —
you coordinate, you do not implement. All spec reading, task creation, coding,
and validation is done by teammates you spawn via agent teams.

The goal: implement the entire `example-tool` project as defined in
`TECHNICAL-SPEC.md`, producing a compilable Rust binary.

Work proceeds in three sequential phases. Create one agent team per phase,
shut it down and clean it up before starting the next.

---

## Phase 1: Spec Decomposition

<phase_1>

### Objective

Break `TECHNICAL-SPEC.md` into self-contained module documents sized for a
single agent's context window. Each document must contain everything an
implementing agent needs for that module without requiring the full
1,200-line spec.

### Team Setup

Create a team. Spawn 4 teammates. Each teammate handles 3-4 spec sections.

In each spawn prompt, tell the teammate:
- The exact section numbers and line ranges they are responsible for.
- The output file path(s) they should write to.
- The formatting rules below.

### Output

Create a `spec/` directory with these files:

| File | Spec Sections |
|------|---------------|
| `spec/01-cli-surface.md` | Section 5.1 |
| `spec/02-config-system.md` | Section 7 |
| `spec/03-data-model.md` | Sections 3, 6.1 |
| `spec/04-storage-layer.md` | Section 6.2-6.3 |
| `spec/05-auth-module.md` | Section 4.1-4.3 |
| `spec/06-api-client.md` | Section 4.4-4.6 |
| `spec/07-core-commands.md` | Sections 5.2-5.5 |
| `spec/08-advanced-commands.md` | Sections 5.6-5.8 |
| `spec/09-output-formatting.md` | Section 8 |
| `spec/10-error-handling.md` | Section 6.4 |
| `spec/11-testing-strategy.md` | Section 9 |
| `spec/12-build-deploy.md` | Section 10 |

### Rules for Each Module Document

1. Self-contained — include all relevant details inline. Do not write "see
   TECHNICAL-SPEC.md" or summarize.
2. Preserve verbatim — exact names, types, flag names, error messages.
3. Cross-references at the top.
4. Under 400 lines each.

### Validation

After all module docs are written, spawn one more teammate to validate.
Read full spec + all module docs. Write `spec/VALIDATION.md` listing
omissions or drift. Phase 1 completes only when zero issues reported.

Shut down all teammates and clean up the team before proceeding.

</phase_1>

---

## Phase 2: Task Planning

<phase_2>

### Objective

Create independently implementable tasks with file-based tracking.

### Team Setup

Create a new team. Spawn 3 teammates.

### Output

tasks/ directory with todo/, in-progress/, to-validate/, done/ subdirectories.

### Ordering

1. Project scaffolding (Cargo.toml, module layout, error types)
2. Configuration system (config file parsing, defaults)
3. Data model (core types, serialization)
4. Storage layer (read/write, migrations)
5. Authentication module (login, token refresh, session management)
6. API client (HTTP layer, request/response types)
7. Core commands (list, show, create, update, delete)
8. Advanced commands (search, export, bulk operations)
9. Output formatting (table, JSON, human-readable)
10. Integration tests

### Validation

Coverage mapping, DAG validity, sizing limits, file exclusivity.
Phase 2 completes when validation passes.

</phase_2>

---

## Phase 3: Implementation

<phase_3>

### Team Setup

- Implementers: `impl-1`, `impl-2`, `impl-3`
- Validators: `validator-1`, `validator-2`

### Completion Criteria

1. All task files are in `tasks/done/`.
2. `cargo build --release` succeeds with no warnings.
3. `cargo clippy -- -D warnings` passes.
4. `cargo test` passes.

</phase_3>

---

## Orchestrator Constraints

<constraints>
- Stay in delegate mode. Do not read spec sections, write code, or run builds.
- One team at a time.
- Maximize parallelism for independent work.
- Provide full context in spawn prompts.
- Document ambiguities in DECISIONS.md.
- Implement exactly what the spec describes.
- Do not escalate to the user.
</constraints>
