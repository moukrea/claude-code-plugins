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

That's it. On first load, the plugin checks prerequisites and creates a CLI symlink at `~/.claude-switcher/cli` so all slash commands resolve automatically -- you never need to know or type the plugin's install path.

**Requires**: bash 4.0+, [jq](https://jqlang.github.io/jq/download/)

## Quick Start

Everything is done through slash commands inside Claude Code:

1. `/setup` — inject rate limit capture into status line
2. `/save work` — save your current logged-in account
3. Log in to the other account: `! claude auth logout && claude auth login`
4. `/save personal` — save the second account
5. `/auto-config enable` — enable auto-switching
6. `/auto-config primary work` — set primary profile
7. `/auto-config fallback personal` — set fallback profile
8. `/auto-config threshold 97` — switch at 97% usage
9. `/auto-config daily-reset 15:00 Europe/Paris` — set daily reset time

## Slash Commands

Once installed as a plugin, use these in Claude Code sessions:

| Command | Description |
|---------|-------------|
| `/save <name>` | Save current account as a named profile |
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

All configuration is done via the `/auto-config` slash command:

| Command | Description |
|---------|-------------|
| `/auto-config` | View current config |
| `/auto-config enable` | Enable auto-switching |
| `/auto-config disable` | Disable auto-switching |
| `/auto-config primary work` | Set primary profile |
| `/auto-config fallback personal` | Add fallback profile |
| `/auto-config threshold 97` | Switch at 97% real usage |
| `/auto-config daily-reset 15:00 Europe/Paris` | Set daily reset time |
| `/auto-config weekly-reset Monday 10:00` | Set weekly reset time |
| `/auto-config reset-state` | Clear auto-switch state |

## CLI Reference

All commands are also available via the script directly:

```
~/.claude-switcher/cli <command> [options]

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
~/.claude-switcher/cli uninstall
```
