---
name: limit-hit
description: "Manually trigger a rate limit fallback switch. Use when Claude Code hits a rate limit and auto-detection didn't catch it, or when the user says they've hit their limit."
allowed-tools: Bash
---

# Rate Limit Hit -- Manual Fallback

The user is reporting they've hit a rate limit. Trigger the fallback switch:

```bash
$CLAUDE_PLUGIN_ROOT/scripts/claude-switcher.sh limit-hit
```

After running:
1. Tell the user which profile they've been switched to
2. Explain that the tool will auto-switch back to the primary profile at the configured reset time
3. If it fails (auto-switch not enabled or no fallback configured), help them set it up:
   - `$CLAUDE_PLUGIN_ROOT/scripts/claude-switcher.sh auto-config enable`
   - `$CLAUDE_PLUGIN_ROOT/scripts/claude-switcher.sh auto-config primary <name>`
   - `$CLAUDE_PLUGIN_ROOT/scripts/claude-switcher.sh auto-config fallback <name>`
