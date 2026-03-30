---
name: who
description: "Show which Claude Code account profile is currently active. Use when the user asks who they're logged in as, which profile/account is active, or wants a quick status check."
allowed-tools: Bash
---

# Current Profile

Show the user which profile is active right now:

```bash
~/.claude-switcher/cli status
```

Present the key info concisely:
- Active profile name
- Email and subscription type
- Rate limit usage (if auto-switch is enabled)
- Whether they're on a fallback profile (if applicable)
