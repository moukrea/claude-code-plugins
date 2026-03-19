---
name: recovery
description: Recover from failure state by analyzing errors, optionally reverting
  changes, and re-planning. Use when implementation is stuck or tests are
  persistently failing.
---

Recover from the current failure state.

Process:
1. Analyze recent git history for potentially problematic changes:
   !`git log --oneline -10`
   !`git diff --stat HEAD~3 2>/dev/null || echo "not enough history"`

2. Check current test status:
   !`npm test 2>&1 | tail -20 || cargo test 2>&1 | tail -20 || pytest 2>&1 | tail -20 || echo "no test command found"`

3. Based on findings:
   - If a specific recent commit broke things: consider `git revert`
   - If the approach is fundamentally wrong: discuss with user before reverting
   - If it's a fixable error: fix it directly
   - If tests are timing out: check for infinite loops or missing mocks

4. After recovery, run verification to confirm the fix.

NEVER revert commits without confirming with the user first if the revert
affects more than the current task.
