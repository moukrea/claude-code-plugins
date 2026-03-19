# harness — Behavioral Rules

These rules apply whenever the harness plugin is installed. They govern how you
respond to harness hook context and work with the agent orchestration system.

## How hooks work

Hook messages appear as `[HARNESS]` prefixed context. Act on them according to
the rules below. Hooks provide facts and recommendations — you decide the response.

## Rule 1: Respect complexity classification

When the harness classifies a prompt, adapt your approach:

| Classification | Recommended approach |
|----------------|---------------------|
| `simple` | Proceed directly — no planning overhead |
| `medium` | Explore the codebase, plan, then implement with verification |
| `complex` | Decompose into tasks, use subagents for parallel work, verify each piece |
| `massive` | Ingest spec fully, decompose into granular tasks, use agent teams or batch processing |

If the harness flags a prompt as vague, clarify requirements before starting work.
Use the `/harness:requirements-interview` skill for structured gathering.

## Rule 2: Never remove tests

The harness blocks removal of existing test cases. Tests must only be added or
modified, never removed. If you need to change test behavior, update the test
assertions — do not delete the test function.

This applies to any file matching test patterns (`*.test.*`, `*.spec.*`,
`*_test.*`, `test_*.*`, `__tests__/`, etc.).

## Rule 3: Fix failures before stopping

The harness runs the project's test suite and linter before allowing a session
to stop. If tests or lint fail, you must fix the issues before the session can end.

Similarly, when a task is marked complete, the harness verifies tests pass. Do not
mark tasks as complete until verification succeeds.

## Rule 4: No incomplete implementations

When operating as a spawned implementer agent, the harness checks for incomplete
markers before allowing you to stop. Do not leave `TODO`, `FIXME`, `not yet
implemented`, `placeholder`, or `stub` markers in your output.

## Rule 5: Use detected project commands

At session start, the harness detects the project type and its test, lint, and
build commands. Use these detected commands for verification rather than guessing.
The harness injects them as context — reference them when running checks.

## Rule 6: Act on failure patterns

The harness tracks consecutive bash failures. When you see a failure pattern
warning (3+ similar failures), change your approach rather than retrying the
same command. Consider:
- Reading error output carefully
- Trying an alternative approach
- Using the `/harness:recovery` skill

## Rule 7: Lock file caution

When the harness warns about lock file edits, do not edit lock files directly.
These are generated files — use the appropriate package manager command instead
(`npm install`, `cargo update`, etc.).

## Rule 8: Agent team coordination

When working with agent teams:
- The **architect** decomposes work and creates tasks
- The **implementer** works in isolated worktrees on single tasks
- The **tester** writes and runs tests
- The **reviewer** checks code quality
- The **integrator** merges parallel work and resolves conflicts
- The **debugger** diagnoses and fixes errors
- The **monitor** watches long-running processes
- The **researcher** explores the codebase deeply
- The **ui-verifier** validates visual implementations

Each agent has specific tools and constraints. Respect agent boundaries — do not
ask an implementer to do architecture work or a researcher to write code.

## Rule 9: Post-edit verification

The harness runs per-file type checking after edits (TypeScript, Python, Go,
JavaScript). If verification errors appear in the additional context, fix them
before moving on. Do not accumulate type errors across multiple edits.

## Rule 10: Compaction awareness

Before context compaction, the harness snapshots git state. After compaction,
it reports any changes detected. If you see post-compaction context about branch
changes, new commits, or modified file count changes, re-orient yourself before
continuing work.

## Skill reference

| Skill | When to use |
|-------|-------------|
| `/harness:init` | Initialize harness for a new project (run once per project) |
| `/harness:session-bridge` | Resume work from a previous session |
| `/harness:task-analyze` | Analyze task complexity before starting |
| `/harness:task-decompose` | Break complex work into parallel tasks |
| `/harness:requirements-interview` | Gather requirements for vague tasks |
| `/harness:spec-ingest` | Ingest a specification document |
| `/harness:verify-work` | Comprehensive verification of completed work |
| `/harness:progress-report` | Generate a progress summary |
| `/harness:recovery` | Recover from stuck or failing state |
| `/harness:reflect` | Reflect on improvements after milestones |
| `/harness:deployment-monitor` | Monitor a deployment or CI pipeline |
| `/harness:logs` | Review harness hook activity logs |
