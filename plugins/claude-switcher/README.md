# claude-switcher

Switch between multiple Claude Code accounts instantly. Auto-switches on rate limits and switches back when they reset.

## Why

If you have multiple Claude Max subscriptions (e.g., a work account and a personal one), switching between them normally requires logging out and back in every time. claude-switcher saves your accounts as named profiles and swaps credentials instantly -- no network calls, no re-authentication.

When your primary account hits rate limits, it can automatically switch to your fallback account, then switch back when the limits reset.

## Install

```bash
claude mcp  # open plugin manager, search for "claude-switcher"
```

Or register manually:

```bash
claude --plugin-dir /path/to/claude-switcher
```

On first load, the plugin:
- Checks that `jq` is installed (required dependency)
- Creates a CLI symlink at `~/.claude-switcher/cli`
- Sets up rate limit capture and auto-switch in your status line

**Requires**: [jq](https://jqlang.github.io/jq/download/)

## Getting Started

### 1. Save your first account

While logged into your first Claude account:

```
/save work
```

This saves the current credentials as a profile named "work".

### 2. Log in to your second account

```
! claude auth logout && claude auth login
```

### 3. Save the second account

```
/save personal
```

### 4. Switch between accounts

```
/switch work        # switch to work profile
/switch personal    # switch to personal profile
/switch prev        # switch back to the previous profile
```

### 5. Check which account is active

```
/who
```

Shows the active profile name, email, subscription type, and rate limit usage.

## Auto-Switch

claude-switcher can automatically switch to a fallback account when your primary hits rate limits, and switch back when they reset.

### Enable auto-switch

```
/auto-config enable
/auto-config primary work
/auto-config fallback personal
/auto-config threshold 97
```

This tells claude-switcher:
- **primary**: Use "work" by default
- **fallback**: Switch to "personal" when rate-limited
- **threshold**: Switch preemptively at 97% usage (before hitting the hard limit)

### How it works

The plugin injects a small helper into your Claude Code status line script. On every status line refresh (which happens continuously), it:

1. Reads your current rate limit usage directly from Claude Code
2. Compares it against your configured threshold
3. If usage exceeds the threshold, it switches to the fallback profile
4. When on fallback, it checks if the primary's rate limits have reset and switches back

A `StopFailure` hook also serves as a safety net -- if you hit an actual rate limit error, it detects it and switches.

### Show profile in status line

To see which account is active at all times in your status line:

```
/auto-config show-profile enable
```

This shows `[work]` or `[personal FALLBACK]` in the status bar. It's off by default.

### View auto-switch status

```
/auto-config
```

Shows: enabled/disabled, primary, fallbacks, threshold, current rate limits, and whether you're on a fallback.

### Manual fallback

If auto-detection misses a rate limit:

```
/limit-hit
```

## Slash Commands

| Command | Description |
|---------|-------------|
| `/who` | Show active profile (name, email, subscription, rate limits) |
| `/save <name>` | Save current account as a named profile |
| `/switch <name>` | Switch to a profile (`prev` for previous) |
| `/profiles` | List all saved profiles |
| `/auto-config [...]` | View or configure auto-switching |
| `/limit-hit` | Manually trigger fallback switch |
| `/setup` | Re-run status line setup (idempotent) |
| `/cli <command>` | Run any CLI command directly |

### Auto-config subcommands

| Subcommand | Description |
|------------|-------------|
| `show` | View current configuration (default) |
| `enable` / `disable` | Toggle auto-switching |
| `primary <name>` | Set the primary (preferred) profile |
| `fallback <name>` | Add a fallback profile |
| `threshold <percent>` | Preemptive switch threshold (default: 97) |
| `show-profile enable` / `disable` | Toggle profile name in status line |
| `reset-state` | Clear auto-switch state |

### CLI commands (via `/cli`)

For operations without a dedicated slash command:

```
/cli status           # full status with live auth check
/cli show work        # detailed info for a profile
/cli delete old-acct  # delete a profile
/cli rename old new   # rename a profile
/cli version          # show version
```

## How It Works

**Profile storage**: Each profile is saved in `~/.claude-switcher/profiles/<name>/` with credentials and account metadata. Switching copies credentials to `~/.claude/.credentials.json` and updates `~/.claude.json`.

**Status line integration**: The `/setup` command injects three snippets into your status line script:
1. **Rate limit capture** -- writes fresh rate limit data to `~/.claude-switcher/rate-limits.json`
2. **Auto-switch** -- checks thresholds and triggers switches (async, non-blocking)
3. **Profile indicator** -- shows the active profile name (when enabled)

**Security**: Profile directories are `chmod 700`, credential files are `chmod 600`. No credentials are sent over the network. All writes use atomic temp-file-then-rename.

## Uninstall

```
/cli uninstall
```
