---
name: setup
description: "Set up claude-switcher rate limit capture by injecting a snippet into the Claude Code status line script. Use when the user first installs the plugin or asks to configure rate limit tracking."
allowed-tools: Bash
---

# Set Up Claude-Switcher

Run the setup command to configure rate limit capture:

```bash
~/.claude-switcher/cli setup-plugin
```

This injects a small snippet into the user's Claude Code status line script that captures real rate limit data (five_hour and seven_day percentages) to `~/.claude-switcher/rate-limits.json`. This data is then used by the auto-switch system to preemptively switch profiles before hitting rate limits.

After setup, guide the user through configuring auto-switch if not done already:
1. Save both profiles with `/save <name>`
2. Enable auto-switch with `/auto-config enable`
3. Set primary and fallback profiles with `/auto-config primary <name>` and `/auto-config fallback <name>`
4. Set threshold with `/auto-config threshold 97`
