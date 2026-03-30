---
name: auto-config
description: "View or configure auto-switching settings for Claude Code account profiles. Use when the user asks about auto-switch configuration, wants to change primary/fallback profiles, or adjust thresholds."
argument-hint: "[show | enable | disable | primary <name> | fallback <name> | threshold <pct> | show-profile enable|disable | reset-state]"
allowed-tools: Bash
---

# Auto-Switch Configuration

Manage automatic profile switching configuration.

If no argument provided, show the current config:
```bash
~/.claude-switcher/cli auto-config show
```

If argument provided, run the matching subcommand:
```bash
~/.claude-switcher/cli auto-config $ARGUMENTS
```

After showing config, explain what each setting means:
- **Primary**: The preferred account, consumed first
- **Fallbacks**: Accounts to switch to when primary hits rate limits
- **Threshold**: Switch when real usage (from status line) exceeds this percentage
- **Status line**: Whether to show the active profile name in the status line
- **Rate limits**: Current 5-hour and 7-day usage with actual reset timestamps from Claude Code
- **Switch-back**: Automatic — uses real `resets_at` timestamps from the rate limit data

If the user is setting up auto-switch for the first time, guide them:
1. Run `/setup` first to enable rate limit capture in the status line
2. `/auto-config enable`
3. `/auto-config primary work`
4. `/auto-config fallback personal`
5. `/auto-config threshold 97` (switch at 97% real usage)
6. `/auto-config show-profile enable` (optional: show profile in status line)

Auto-switching runs via the status line script (injected by `/setup`). It reads rate limit data on every render and switches when the threshold is exceeded. When on fallback, it automatically switches back when the primary's limits reset.
