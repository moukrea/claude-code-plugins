---
name: task-decompose
description: Decompose a complex task into independent, parallelizable work units.
  Each unit has clear acceptance criteria, file boundaries, and verification steps.
  Use when work is classified as complex or massive.
context: fork
agent: architect
---

Decompose this task into independent work units: $ARGUMENTS

ultrathink about the decomposition strategy.

Rules:
1. Each unit MUST be independently verifiable
2. Units MUST have minimal file overlap (avoid merge conflicts in parallel work)
3. Each unit MUST have explicit acceptance criteria
4. Order units by dependency (note which are blocked by others)
5. Target 5-6 units per agent (from Anthropic agent teams best practices)
6. Each unit should be completable in a single focused session

For each unit, specify:
- Description (one sentence)
- Files likely affected
- Acceptance criteria (testable, specific)
- Dependencies (which other units must complete first)
- Verification command

After decomposition, create tasks via TaskCreate for each unit.

For additional decomposition patterns, see [templates](templates/decomposition-template.md).
For examples of good decompositions, see [examples](examples/good-decompositions.md).
