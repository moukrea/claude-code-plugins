# claude-switcher

Claude Code plugin for switching between multiple Claude Max accounts. Auto-switches on rate limits and switches back at reset time.

## Why

If you have both a company Claude Max subscription (limited usage) and a personal one, switching accounts normally requires `claude auth logout` then `claude auth login` every time.

claude-switcher saves named profiles and restores them instantly -- zero network calls. Plus it auto-switches to your fallback account when you hit rate limits, and auto-switches back when the primary resets.

## Install

Register as a Claude Code plugin:

```bash
claude --plugin-dir /path/to/claude-switcher
```

Or add to `~/.claude/settings.json`:

```json
{
  "plugins": ["/path/to/claude-switcher"]
}
```

**Requires**: bash 4.0+, [jq](https://jqlang.github.io/jq/download/)

## Quick Start

```bash
# Set up rate limit capture
./scripts/claude-switcher.sh setup-plugin

# Save your current account
./scripts/claude-switcher.sh save work

# Log in to the other account
claude auth logout && claude auth login

# Save that one too
./scripts/claude-switcher.sh save personal

# Configure auto-switching
./scripts/claude-switcher.sh auto-config enable
./scripts/claude-switcher.sh auto-config primary work
./scripts/claude-switcher.sh auto-config fallback personal
./scripts/claude-switcher.sh auto-config threshold 97
./scripts/claude-switcher.sh auto-config daily-reset 15:00 Europe/Paris
```

## Slash Commands

Once installed as a plugin, use these in Claude Code sessions:

| Command | Description |
|---------|-------------|
| `/switch <name>` | Switch to a profile |
| `/switch prev` | Switch to previous profile |
| `/profiles` | List all profiles |
| `/limit-hit` | Manually trigger fallback (rate limit) |
| `/auto-config` | View/edit auto-switch configuration |
| `/setup` | Set up rate limit capture in status line |

## Auto-Switch

When enabled, claude-switcher automatically manages account switching:

1. **Preemptive**: A `PostToolUse` hook reads real rate limit data (captured from the status line) and switches at a configurable threshold (default 97%) BEFORE hitting the actual limit
2. **On rate limit**: A `StopFailure` hook detects actual rate limit errors as a safety net
3. **On reset**: A `SessionStart` hook checks if the primary account's limit has reset and switches back
4. **Manual**: Use `/limit-hit` if auto-detection misses a rate limit

### Configuration

```bash
./scripts/claude-switcher.sh auto-config show          # View config
./scripts/claude-switcher.sh setup-plugin                # Inject rate limit capture into status line
./scripts/claude-switcher.sh auto-config enable         # Enable
./scripts/claude-switcher.sh auto-config primary work   # Set primary
./scripts/claude-switcher.sh auto-config fallback personal  # Add fallback
./scripts/claude-switcher.sh auto-config threshold 97   # Switch at 97% real usage
./scripts/claude-switcher.sh auto-config daily-reset 15:00 Europe/Paris
./scripts/claude-switcher.sh auto-config weekly-reset Monday 10:00
./scripts/claude-switcher.sh auto-config reset-state    # Clear state
```

## CLI Reference

All commands are also available via the script directly:

```
./scripts/claude-switcher.sh <command> [options]

Profile Management:
  save <name> [--force]     Save current auth as a profile
  use <name>                Switch to a profile
  prev, -                   Switch to previous profile
  list                      List profiles
  show <name>               Profile details
  status                    Active profile + auto-switch state
  delete <name>             Delete a profile
  rename <old> <new>        Rename a profile
  setup                     Interactive first-time setup

Auto-Switch:
  auto-config [subcmd]      Configure auto-switching
  limit-hit                 Manually trigger fallback

Other:
  uninstall                 Remove plugin registration
  help                      Show help
  version                   Show version
```

## How It Works

**Profile switching**: Copies OAuth tokens from `~/.claude-switcher/profiles/<name>/` back to `~/.claude/.credentials.json` and surgically updates only the `oauthAccount` key in `~/.claude.json`.

**Rate limit capture**: The `/setup` command injects a snippet into your Claude Code status line script. The status line receives real rate limit data from Claude Code (five_hour and seven_day percentages) on every refresh, and the snippet writes this to `~/.claude-switcher/rate-limits.json`.

**Preemptive switching**: The `PostToolUse` hook (async, non-blocking) reads the captured rate limit data after every tool call. When either the 5-hour or 7-day usage exceeds the configured threshold, it switches to the fallback before hitting the actual limit.

**Rate limit detection**: The `StopFailure` hook serves as a safety net. It analyzes errors for rate-limit patterns and switches if the preemptive system missed.

**Time-based switch-back**: The `SessionStart` hook checks if the configured daily reset time has passed. If the primary account was rate-limited but has since reset, it auto-switches back.

## Security

- Profile directories: `chmod 700`
- Credential files: `chmod 600`
- No credentials sent over the network
- Atomic writes (temp file + mv)
- Backup state preserved before every switch

## Uninstall

```bash
./scripts/claude-switcher.sh uninstall
```
