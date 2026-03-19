---
name: progress-report
description: Generate a comprehensive progress report showing completed tasks,
  pending work, blockers, and overall project health.
disable-model-invocation: true
---

Generate a progress report for the current project.

Include:
1. **Task summary**: completed / in-progress / pending (from task list)
2. **Recent activity**: last 10 git commits with file counts
3. **Test health**: run test suite, report pass/fail
4. **Code quality**: run lint, report issues
5. **Blockers**: any stuck tasks or recurring failures

Format as a clear, concise summary the user can scan in 30 seconds.
