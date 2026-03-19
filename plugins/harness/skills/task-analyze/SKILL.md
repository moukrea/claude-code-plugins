---
name: task-analyze
description: Analyze a task's complexity and recommend the execution strategy. Maps
  to simple (direct), medium (subagent-assisted), complex (parallel subagents), or
  massive (agent team/batch). Use automatically when evaluating new work.
user-invocable: false
---

Analyze this task for complexity: $ARGUMENTS

Classification criteria:
| Level   | Files  | Signal                                        | Strategy            |
|---------|--------|-----------------------------------------------|---------------------|
| Simple  | 1-3    | Bug fix, typo, config, single-file change     | Direct execution    |
| Medium  | 3-10   | Feature, refactor, test addition              | Researcher + plan   |
| Complex | 10-30  | Cross-cutting change, multi-module feature    | Parallel subagents  |
| Massive | 30+    | Full spec, migration, new project from scratch| Agent team or /batch|

Also assess:
- Does this need an interview? (vague request + medium+ complexity)
- Does this need a plan? (medium+ complexity)
- What effort level? (low/medium/high/max mapping to complexity)
- Are there cross-cutting concerns? (API + DB + UI + tests = complex)

Report your classification naturally as part of your response. Do NOT use
harness terminology -- just act on the classification.
