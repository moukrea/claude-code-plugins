# harness — Agent Orchestration Harness

Transparent harness for long-running Claude Code agents. Automatically classifies tasks, decomposes complex work, tracks progress, verifies output, bridges sessions, and adapts to any project type. Zero configuration required.

## What it does

- Classifies prompt complexity (simple → massive) and recommends an execution strategy
- Guards against test removal, lock file edits, and incomplete implementations
- Runs tests and lint before allowing a session to stop or a task to be marked complete
- Tracks failure patterns and suggests recovery after repeated errors
- Detects project type at session start (Node.js, Rust, Go, Python, etc.) and injects verification commands
- Preserves git state across context compaction so you don't lose orientation
- Provides 9 specialized agent definitions for parallel team workflows

## In practice

```
You: "Refactor the authentication system to use JWT tokens,
      update all API endpoints, and add comprehensive tests"

Claude: [HARNESS] Task classified as complex.
        Consider: decompose into tasks, use subagents
        for parallel work, verify each piece.
        -> Decomposes into auth module, endpoint migration, test suite
        -> Spawns implementer agents in isolated worktrees
        -> Verifies tests pass before marking each task complete
        -> Blocks session stop until all tests and lint pass
```

## Skills

| Skill | Description |
|-------|-------------|
| `/harness:init` | Initialize harness for a project — detects languages, creates rules |
| `/harness:session-bridge` | Resume work from a previous session with live state injection |
| `/harness:task-analyze` | Analyze task complexity and recommend execution strategy |
| `/harness:task-decompose` | Break complex work into independent, parallelizable units |
| `/harness:requirements-interview` | Gather detailed requirements for vague tasks |
| `/harness:spec-ingest` | Ingest a specification document into granular feature units |
| `/harness:verify-work` | Run comprehensive verification (tests, lint, build, types) |
| `/harness:progress-report` | Generate a summary of completed tasks, pending work, blockers |
| `/harness:recovery` | Recover from stuck state — analyze errors, revert, re-plan |
| `/harness:reflect` | Suggest configuration improvements after completing complex work |
| `/harness:deployment-monitor` | Monitor a deployment, CI pipeline, or PR status |
| `/harness:logs` | Summarize recent harness hook activity for debugging |

## Hooks

| Hook | Trigger | Action |
|------|---------|--------|
| Session start | New session | Detects project type, test/lint/build commands, git status |
| Prompt classify | Each prompt | Classifies complexity, recommends execution strategy |
| Write guard | Write, Edit | Blocks test removal and warns on lock file edits |
| Post-edit | Write, Edit | Runs per-file type checking (TypeScript, Python, Go, JS) |
| Failure tracker | Bash failures | Tracks patterns, warns after 3+ similar failures |
| Task gate | Task completion | Verifies tests pass before allowing task completion |
| Stop gate | Session stop | Verifies tests and lint pass before allowing stop |
| Implementation check | Implementer stop | Blocks incomplete work (TODO, placeholder, stub) |
| Pre/post compact | Context compaction | Preserves and restores git state across compaction |

## Agent Definitions

The harness includes 9 specialized agent roles for team workflows:

| Agent | Role | Model |
|-------|------|-------|
| Architect | System design, task decomposition, planning | Opus |
| Implementer | Focused single-task coding in isolated worktrees | Default |
| Tester | Test writing and verification | Default |
| Reviewer | Code quality, security, and consistency review | Sonnet |
| Debugger | Root cause analysis and minimal fixes | Default |
| Integrator | Merge conflict resolution and integration validation | Default |
| Researcher | Deep codebase exploration and analysis | Sonnet |
| Monitor | Long-running process and CI pipeline tracking | Haiku |
| UI Verifier | Visual verification via browser automation | Sonnet |

## Project Detection

The harness auto-detects the project environment at session start:

| Project Type | Test | Lint | Build |
|-------------|------|------|-------|
| Node.js (TypeScript) | `npm test` | `npm run lint` | `npm run build` |
| Rust | `cargo test` | `cargo clippy` | `cargo build` |
| Go | `go test ./...` | `golangci-lint run` | `go build ./...` |
| Python | `pytest` | `ruff check .` | — |
| Make-based | `make test` | — | `make build` |

## Rule Templates

Language-specific rules are available for project initialization (`/harness:init`):

`database` · `frontend` · `go` · `infrastructure` · `python` · `rust` · `testing` · `typescript`

## Installation

```
/plugin install harness@moukrea-plugins
```
