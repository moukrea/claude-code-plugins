# QA Report -- Round 2

## Verdict: PASS

## Scores
- **Product Depth**: 8/10 (threshold: 6) -- All iteration 3 features fully implemented with depth: status-line-driven auto-switch, setup idempotency, profile indicator opt-in, /cli and /who commands, edge case handling
- **Functionality**: 8/10 (threshold: 7) -- Critical switch-back bug is fixed; all core flows work correctly including forward switch, switch-back, profile indicator, setup idempotency, and error handling
- **Visual Design**: N/A (CLI tool)
- **Code Quality**: 7/10 (threshold: 5) -- Clean modular structure, proper quoting, atomic writes, good error messages, shellcheck annotations, consistent patterns across all lib files

## Tests Performed

### Critical fix verification: switch-back ordering
1. Read `~/.claude-switcher/statusline-autoswitch.sh` lines 44-52: confirmed `original_profile` is read (line 47) BEFORE `reset-state` is called (line 48)
2. Read `scripts/lib/setup.sh` lines 166-172 (embedded HEREDOC): confirmed same correct ordering in the template
3. Ran end-to-end switch-back test:
   - Created simulated fallback state: `on_fallback=true`, `original_profile=work`, `switch_back_at` set to 1 hour in the past
   - Sourced `statusline-autoswitch.sh` with valid `$input` JSON
   - Verified state file reset (`on_fallback=false`, `original_profile=null`)
   - Verified active profile switched to `work` (the original)
   - This is the exact reproduction case from round 1 that previously failed

### hooks.json validation
- Parsed with jq: valid JSON
- Contains exactly 2 events: SessionStart, StopFailure
- PostToolUse is NOT present: `jq 'has("PostToolUse")' hooks/hooks.json` returns false
- `scripts/on-post-tool-use.sh` does not exist (confirmed deleted)

### CLI basics
- `version`: returns "claude-switcher 3.0.0"
- `help`: displays full command list including `show-profile` subcommand
- `auto-config show`: displays all fields including "Status line" field, resets_at timestamps

### auto-config show-profile subcommand
- `show-profile` (no args): shows current value + usage hint
- `show-profile enable`: sets `show_in_statusline=true` in auto-switch.json
- `show-profile disable`: sets `show_in_statusline=false`

### statusline-autoswitch.sh scenarios
- **Below threshold** (50% 5h, 30% 7d, threshold 97%): No CLI calls spawned -- PASS
- **Above threshold** (98% 5h, threshold 97%): `check-limits` spawned async (confirmed via `set -x` trace) -- PASS
- **On fallback, past switch_back_at**: Reads original_profile correctly, resets state, switches back -- PASS (was the critical bug, now fixed)
- **On fallback, future switch_back_at**: No CLI calls -- PASS
- **Auto-switch disabled** (99% usage): No CLI calls -- PASS

### statusline-profile.sh
- `show_in_statusline=false`: indicator is empty string -- PASS
- `show_in_statusline=true`, normal: shows `[work] ` -- PASS
- `show_in_statusline=true`, on fallback: shows `[work FALLBACK] ` -- PASS

### End-to-end status line simulation
- Piped JSON through `~/.claude/statusline-command.sh`
- With indicator disabled: no `[work]` prefix
- With indicator enabled: `[work]` prefix in purple ANSI
- `rate-limits.json` written correctly with both windows and resets_at

### SessionStart hook
- Normal state: outputs JSON with profile info, email, org, subscription, rate limits
- Fallback state: includes fallback reason, original profile, switch-back time in human-readable format
- Does NOT contain switch/mismatch logic (display only)

### StopFailure hook
- Rate limit error: triggers switch to fallback profile
- Non-rate-limit error: silently exits without switching

### setup-plugin idempotency
- Second run reports "already configured" for all 3 stages
- No duplicate markers in status line script (each appears exactly once)
- Helper scripts re-installed on every run (idempotent write)

### CLI commands (regression)
- `list`: shows both profiles with active marker
- `show work`: displays all profile details
- `prev`: switches to previous profile
- `use work`: switches back
- `auto-config reset-state`: clears state correctly
- `auto-config threshold 95/97`: validates and persists

### Edge cases
- Empty `$input`: no crash, exit 0
- Malformed JSON input: no crash, exit 0
- Missing `rate_limits` in JSON: no crash, exit 0
- Missing config files: no crash, exit 0
- Unknown subcommand: proper error message with exit code 1
- Unknown top-level command: proper error with exit code 1
- Empty profile name: proper validation error
- Nonexistent profile: proper error message
- Threshold validation: rejects 0, 101, and non-numeric input

### Commands (slash commands)
- `cli.md`: valid frontmatter with name, description, argument-hint, allowed-tools
- `who.md`: valid frontmatter, references `~/.claude-switcher/cli status`

## Issues Found

### Critical (must fix)
- None

### Warning (should fix)
- None

### Note (minor, optional)
- The embedded HEREDOC in `setup.sh` is missing one comment line (`# Mismatch -- find the correct profile and update config`) that exists in the installed file. Cosmetic only, no functional impact.
- The `do_auto_switch_back` function in `auto-state.sh` (lines 147-159) was already correct in round 1 (reads original before clearing state). The bug was only in the status-line helper. Both paths are now consistent.

## Spec Coverage

| Feature | Status | Notes |
|---------|--------|-------|
| statusline-autoswitch.sh helper | ✅ Working | Forward switch and switch-back both work correctly; original_profile read before reset-state |
| PostToolUse hook removed | ✅ Working | hooks.json has only SessionStart + StopFailure; on-post-tool-use.sh deleted |
| SessionStart simplified | ✅ Working | Info display only, no switch/mismatch logic |
| Profile indicator opt-in | ✅ Working | show_in_statusline defaults false, statusline-profile.sh respects flag, visible in status line output |
| /cli slash command | ✅ Working | Valid frontmatter, reasonable description, generic passthrough |
| /who slash command | ✅ Working | Valid frontmatter, references CLI status |
| Setup idempotency | ✅ Working | _inject_into_statusline handles 3 stages, markers prevent duplication, warns on missing script |
| auto-config show-profile subcommand | ✅ Working | enable/disable/show all work, persisted in auto-switch.json |
| Version 3.0.0 | ✅ Working | vars.sh shows 3.0.0 |
| Profile mismatch detection (moved to status line) | ✅ Working | Implemented in autoswitch helper with proper profile directory scanning |
| auto-config show displays Status line field | ✅ Working | Shows show_in_statusline value |
| Async spawns (non-blocking) | ✅ Working | check-limits and use both spawned with & |
| Dynamic switch-back timing | ✅ Working | Uses real resets_at timestamps, computes switch_back_at from max of windows above threshold |
| Edge case handling | ✅ Working | Empty input, malformed JSON, missing files all handled gracefully |
| StopFailure safety net | ✅ Working | No matcher restriction, detects rate limit patterns, ignores non-rate-limit errors |

## Feedback for Builder

The critical switch-back ordering bug from round 1 is fully resolved. Both the installed helper at `~/.claude-switcher/statusline-autoswitch.sh` and the embedded template in `scripts/lib/setup.sh` now correctly read `original_profile` before calling `reset-state`. End-to-end testing confirms the switch-back path works as expected.

All other features from the iteration 3 spec continue to work correctly with no regressions. The project is in good shape.
