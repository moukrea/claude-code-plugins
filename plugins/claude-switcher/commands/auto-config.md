---
name: auto-config
description: "View or configure auto-switching settings for Claude Code account profiles. Use when the user asks about auto-switch configuration, wants to change primary/fallback profiles, or adjust thresholds."
argument-hint: "[show | enable | disable | primary <name> | fallback <name> | threshold <pct> | reset-state]"
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
- **Rate limits**: Current 5-hour and 7-day usage with actual reset timestamps from Claude Code
- **Switch-back**: Automatic — uses real `resets_at` timestamps from the rate limit data, not static times

If the user is setting up auto-switch for the first time, guide them through using slash commands:
1. Run `/setup` first to enable rate limit capture in the status line
2. `/auto-config enable`
3. `/auto-config primary work`
4. `/auto-config fallback personal`
5. `/auto-config threshold 97` (switch at 97% real usage)

The **threshold** controls preemptive switching. The PostToolUse hook reads real rate limit data (five_hour and seven_day percentages captured by the status line) and switches to the fallback when either exceeds the threshold. When on fallback, it automatically switches back when the primary's rate limits have actually reset (using the real `resets_at` timestamps from Claude Code).
