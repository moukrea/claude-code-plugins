---
name: verify-work
description: Run comprehensive verification of all completed work. Checks tests,
  lint, build, type errors, and acceptance criteria. Use before declaring any
  significant work complete.
context: fork
agent: tester
---

Run comprehensive verification of the current project state.

Checklist:
1. Run the test suite. Report pass/fail count.
2. Run the linter. Report error count.
3. Run the build (if applicable). Report success/failure.
4. Run type checking (if applicable). Report error count.
5. Check git status -- are there uncommitted changes that should be committed?
6. Review the task list -- are there tasks marked complete that have failing checks?

For each failing check:
- Identify the specific failure
- Suggest the fix
- Estimate effort to fix

Report results as a structured summary.
