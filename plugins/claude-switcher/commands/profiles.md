---
name: profiles
description: "List all saved Claude Code account profiles and show which one is active. Use when the user asks about their accounts, profiles, or wants to see available options."
allowed-tools: Bash
---

# List Claude Code Account Profiles

Show the user their saved profiles:

```bash
$CLAUDE_PLUGIN_ROOT/scripts/claude-switcher.sh list
```

Present the output to the user. The active profile is marked with `*`.

If the user wants more details about a specific profile:
```bash
$CLAUDE_PLUGIN_ROOT/scripts/claude-switcher.sh show <profile-name>
```
