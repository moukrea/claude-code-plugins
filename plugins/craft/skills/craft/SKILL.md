---
name: craft
description: Generate an autonomous implementation prompt (PROMPT.md) from a technical spec or project description. Use when you have a spec file or want to turn a project idea into a full implementation plan that agent teams can execute.
argument-hint: "@spec-file.md or project description"
user-invocable: true
disable-model-invocation: true
---

# craft: Generate Autonomous Implementation Prompts

You are generating a `PROMPT.md` file — an orchestration prompt that coordinates agent teams to implement an entire project autonomously from a technical specification.

## Step 1: Determine Input Mode

Examine the content provided by the user after `/craft`.

**Mode A — Technical Spec Provided**: The input contains structured technical content with multiple heading levels, data types, API definitions, error specifications, or algorithm descriptions. It reads like a specification or design document. Proceed to Step 2.

**Mode B — Description Provided**: The input is a natural language description of what to build. It lacks structured technical sections. You must first generate a technical spec before generating the prompt. Read [spec-generation-guide.md](spec-generation-guide.md) and follow its instructions to produce a `TECHNICAL-SPEC.md`. Once the spec is written, proceed to Step 2 using that spec.

If genuinely uncertain which mode applies, ask the user: "I received your input. Is this a complete technical specification, or a project description that needs to be expanded into a spec first?"

## Step 2: Analyze the Spec

Read the technical spec thoroughly. Extract:

1. **Project metadata**
   - Project name (infer from title or content)
   - Primary language and framework
   - Build, test, and lint commands for that language
   - Target platforms

2. **Spec structure**
   - All top-level sections and their line ranges
   - Estimated line count per section
   - Cross-references between sections (which sections mention concepts defined in other sections)

3. **Architecture components**
   - Major subsystems or modules described in the spec
   - Data models and their relationships
   - External integrations (APIs, databases, OS services)
   - UI/CLI surface area

4. **Complexity estimate**
   - Total spec lines
   - Number of distinct subsystems
   - Estimated module document count (spec lines / 300, rounded up, minimum 5)
   - Estimated task count (module docs * 2-3)

Write a brief analysis summary to the user before proceeding. Example:

> **Spec Analysis**
> - Project: `myproject` (Rust CLI application)
> - Spec size: 850 lines across 8 major sections
> - Architecture: 5 subsystems (data layer, auth, API client, CLI, output formatting)
> - Plan: 6 module documents, ~15 implementation tasks
> - Build commands: `cargo build`, `cargo test`, `cargo clippy -- -D warnings`

## Step 3: Design the Module Document Mapping

Group spec sections into module documents. Each module document must be:

- **Under 400 lines** (leaves room for code and tool output in agent context)
- **Self-contained** — includes all details needed to implement that module
- **Cohesive** — covers a logical unit of functionality

Produce a mapping table:

| Module Document | Spec Sections | Description |
|----------------|---------------|-------------|
| `spec/01-name.md` | sections | what it covers |
| ... | ... | ... |

The naming convention: `NN-kebab-case-name.md`, numbered in logical reading order.

**Grouping heuristics:**
- Keep tightly coupled sections together (e.g., a data model and its serialization)
- Split sections that exceed 400 lines across multiple documents
- Group UI/CLI sections separately from business logic
- Keep platform-specific concerns in their own documents
- Integration points (external APIs, databases) get their own documents

## Step 4: Design the Build Order

Determine the implementation sequence. This is a bottom-up ordering from foundational to high-level:

**Default heuristic (adapt to the specific project):**
1. Project scaffolding — package manager config, module layout, shared error types
2. Data model — core types, serialization, storage
3. External integrations — APIs, databases, OS services, authentication
4. Core business logic — the main algorithms and processing
5. CLI/UI layer — command parsing, user interface, request handling
6. Advanced features — streaming, real-time, caching, optimization
7. Cross-cutting concerns — logging, configuration, monitoring
8. Integration and end-to-end tests
9. Packaging and deployment artifacts

Present this to the user and note any project-specific deviations from the default.

## Step 5: Generate PROMPT.md

Read the [prompt template](prompt-template.md) and the [example prompt](examples/rust-cli-prompt.md) for reference.

Generate a `PROMPT.md` file in the project root using the template, filling in:
- Project name and description
- Spec file path and total line count
- Module document mapping table (from Step 3)
- Language-specific build/test/lint commands
- Build order (from Step 4)
- Team sizing (calculated from spec size)
- Completion criteria specific to the project

### Team Sizing Guidelines

| Spec Size | Phase 1 Agents | Phase 2 Agents | Phase 3 Implementers | Phase 3 Validators |
|-----------|---------------|---------------|---------------------|-------------------|
| < 500 lines | 2-3 | 2 | 2 | 1 |
| 500-1000 lines | 3-4 | 2-3 | 3 | 2 |
| 1000-2000 lines | 4-5 | 3-4 | 3-4 | 2 |
| > 2000 lines | 5-6 | 4-5 | 4-5 | 2-3 |

### Non-Negotiable Invariants

Every generated PROMPT.md must include these patterns. Do not omit or weaken them:

1. **Self-contained module docs** — "Do not write 'see SPEC.md' or summarize. Include all relevant details inline."
2. **Validation agent at every phase gate** — A separate agent checks output against input before proceeding.
3. **Orchestrator stays in delegate mode** — "Do not read spec sections, write code, or run builds yourself."
4. **File-based task tracking** — `tasks/todo/`, `tasks/in-progress/`, `tasks/to-validate/`, `tasks/done/`.
5. **DAG dependencies + file exclusivity** — "No two independent tasks should list the same file in 'Files to Create or Modify.'"
6. **No user escalation** — "Do not escalate to the user. Document ambiguities in DECISIONS.md."
7. **Separate implementer and validator roles** — "A validator must not validate work done by the same agent that implemented it."
8. **Verbatim spec preservation** — "Copy from the spec, do not paraphrase technical specifics."
9. **Sized for context windows** — Module docs under 400 lines, tasks under 4 files and 7 acceptance criteria.
10. **Team-per-phase isolation** — Fresh teams for each phase, shut down before starting the next.

## Step 6: Review and Present

After writing `PROMPT.md`, present a summary to the user:

1. Where the file was written
2. Module document count and names
3. Estimated task count
4. Team sizing per phase
5. The suggested command to execute it:

```
# Open a new Claude Code session and paste the contents of PROMPT.md
# Or: start Claude Code with the file as input
cat PROMPT.md | claude
```

Remind the user to:
- Review the module document mapping for completeness
- Check the build order matches their architecture expectations
- Adjust team sizing if they have cost constraints (fewer agents = cheaper but slower)
- Enable delegate mode (Shift+Tab) before the orchestrator starts working

## Notes

- If the spec file is very large (>2000 lines), consider using a subagent (Task tool) to analyze sections in parallel rather than reading the entire spec in your context.
- If the user provides multiple files (`/craft @spec.md @requirements.md @api-design.md`), treat them as parts of a single spec. Note the file boundaries in the module document mapping.
- The generated PROMPT.md is a standalone document. It does not depend on the craft plugin being installed to execute.
