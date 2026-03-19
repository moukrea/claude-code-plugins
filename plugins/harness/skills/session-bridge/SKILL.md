---
name: session-bridge
description: Orient the current session with live project state. Injects git history,
  test status, and task list to quickly understand where work left off. Use at session
  start or when resuming long-running work.
user-invocable: false
---

## Current Project State

- Git branch: !`git branch --show-current 2>/dev/null || echo "not a git repo"`
- Recent commits: !`git log --oneline -10 2>/dev/null || echo "no git history"`
- Uncommitted changes: !`git diff --stat 2>/dev/null || echo "none"`
- Untracked files: !`git ls-files --others --exclude-standard 2>/dev/null | head -10`

## Your Task

Review the project state above. If there are recent commits suggesting
in-progress work, identify the next logical step. Check the task list
(Ctrl+T) for pending items. Resume the highest-priority incomplete work.
