---
name: auto-config
description: "View or configure auto-switching settings for Claude Code account profiles. Use when the user asks about auto-switch configuration, wants to change primary/fallback profiles, or adjust reset times."
argument-hint: "[show | enable | disable | primary <name> | fallback <name> | threshold <pct> | daily-reset <HH:MM> [tz] | weekly-reset <day> [HH:MM] | reset-state]"
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
- **Daily reset**: When the primary account's daily session limit resets (from the Claude usage screen)
- **Weekly reset**: When the weekly limit resets

If the user is setting up auto-switch for the first time, guide them through using slash commands:
1. Run `/setup` first to enable rate limit capture in the status line
2. `/auto-config enable`
3. `/auto-config primary work`
4. `/auto-config fallback personal`
5. `/auto-config threshold 97` (switch at 97% real usage)
6. `/auto-config daily-reset 15:00 Europe/Paris`
7. `/auto-config weekly-reset Monday 10:00`

The **threshold** controls preemptive switching. The PostToolUse hook reads real rate limit data (five_hour and seven_day percentages captured by the status line) and switches to the fallback when either exceeds the threshold.
