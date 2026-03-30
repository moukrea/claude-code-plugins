---
name: cli
description: "Run any claude-switcher CLI command directly. Use when the user wants to run a specific CLI operation like status, show, delete, rename, version, or any other command not covered by dedicated slash commands."
argument-hint: "<command> [args...]"
allowed-tools: Bash
---

# Claude-Switcher CLI

Run the command directly:

```bash
~/.claude-switcher/cli $ARGUMENTS
```

If no arguments provided, show available commands:
```bash
~/.claude-switcher/cli help
```

Present the output to the user. Common commands:
- `status` — active profile + auto-switch state + live auth
- `show <name>` — detailed profile info
- `list` — all profiles
- `delete <name>` — delete a profile
- `rename <old> <new>` — rename a profile
- `version` — show version
- `auto-config show` — auto-switch configuration
