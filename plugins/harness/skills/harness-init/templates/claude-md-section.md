## Harness

When compacting, always preserve: current task context, acceptance criteria,
modified file list, and verification commands.

### Verification
- Test: `{detected_test_command}`
- Lint: `{detected_lint_command}`
- Build: `{detected_build_command}`

### Workflow
- For complex tasks, explore first (use researcher subagent), then plan, then implement
- Verify work before declaring completion (run tests)
- Use worktree isolation for parallel implementation
- Create tasks via TaskCreate to track multi-step work
