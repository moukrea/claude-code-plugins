# claude-switcher: Dynamic Rate Limit Reset Tracking

## Iteration — 2026-03-30

### Context
The auto-switch system currently uses static daily/weekly reset times (e.g., "15:00 Europe/Paris") to decide when to switch back from fallback to primary profile. However, `rate-limits.json` already contains real `resets_at` epoch timestamps from Claude Code's status line data. These should be used instead, and tracked per-profile so we know when each profile's limits actually reset.

### Bug Found During Investigation
- `rate-limits.sh` reads `.five_hour.percent` but the actual JSON field is `.five_hour.used_percentage`. This causes all rate limit reads to return 0 (the `// 0` fallback). Same bug in `session-start.sh:139-140`.

### Changes Required

1. **Fix field name bug** (`scripts/lib/rate-limits.sh:7,15` and `scripts/session-start.sh:139-140`):
   - Change `.five_hour.percent` → `.five_hour.used_percentage`
   - Change `.seven_day.percent` → `.seven_day.used_percentage`

2. **Per-profile rate limit tracking** (`scripts/lib/rate-limits.sh`):
   - Add `save_rate_limits_for_active_profile()` — copies global rate-limits.json to `profiles/<active>/rate-limits.json`
   - Call this in `check_rate_limits_and_switch()` on every check (async, fast)
   - This ensures each profile has its own rate limit snapshot

3. **Dynamic reset detection** (`scripts/lib/auto-state.sh`):
   - Modify `set_auto_switch_state()` to accept and store `primary_resets_at` object with `five_hour` and `seven_day` epoch timestamps
   - Replace `compute_next_reset()` with logic that computes the switch-back time from actual `resets_at` timestamps: `max()` of all windows that were above threshold
   - Remove `next_reset` field → use `primary_resets_at` with computed earliest safe switch-back time
   - Add config migration to remove deprecated fields (`daily_reset_time`, `daily_reset_timezone`, `weekly_reset_day`, `weekly_reset_time`)

4. **Add switch-back check in check-limits** (`scripts/lib/rate-limits.sh`):
   - When on fallback, check if primary's rate limits have reset (`now >= primary_resets_at`)
   - If so, auto-switch back — more responsive than waiting for SessionStart

5. **Remove deprecated config options** (`scripts/lib/auto-config.sh`):
   - Remove `daily-reset` and `weekly-reset` subcommands from `cmd_auto_config()`
   - Update `show` subcommand to display dynamic reset info instead of static times
   - Update default config to not include deprecated fields
   - Update unknown subcommand error message

6. **Update session-start.sh**:
   - Fix `.percent` → `.used_percentage`
   - Update switch-back logic to use `primary_resets_at` from state instead of `next_reset`
   - Update status messages to show actual reset timestamps

7. **Update command docs** (`commands/auto-config.md`):
   - Remove daily-reset/weekly-reset docs
   - Document new dynamic reset behavior

## Iteration — 2026-03-30 (Auto-switch fixes + /who command)

### Context
Auto-switching doesn't actually work in practice. The user reports that profiles don't switch automatically when rate limit thresholds are reached. Additionally, there's no easy way to see which profile is active from within Claude Code.

### Root Causes Found

1. **StopFailure hook matcher too restrictive** (`hooks/hooks.json`):
   - `"matcher": "rate_limit"` only fires if Claude Code's stop failure reason exactly matches. If the reason string is different (e.g. "overloaded", "rate_limited", "429"), the hook never fires.
   - The `on-stop-failure.sh` script already has robust detection (checking `.error`, `.error_type`, `.message` fields + transcript grep for rate_limit/429/overloaded/etc).
   - Fix: Remove the matcher — let the hook fire for all stop failures, rely on the script's own detection.

2. **No notification when auto-switch happens**:
   - StopFailure hook output is ignored by Claude Code (by design).
   - PostToolUse hook is async, output also ignored.
   - The credential swap happens silently on disk. The current session keeps using old (rate-limited) credentials.
   - Fix: Add profile indicator + fallback alert to the status line, which the user sees constantly.

3. **No way to check current profile from Claude Code**:
   - No slash command exists to quickly show which profile is active.
   - `/profiles` exists but shows a full table — user wants a quick answer.
   - Fix: Add `/who` slash command.

### Changes Required

1. **Remove StopFailure matcher** (`hooks/hooks.json`):
   - Remove `"matcher": "rate_limit"` from the StopFailure hook entry.

2. **Add profile indicator to status line** (`scripts/lib/setup.sh`):
   - Extend the statusline injection snippet to read `~/.claude-switcher/config.json` and display the active profile name.
   - When `auto-switch-state.json` has `on_fallback: true`, show a prominent fallback alert.
   - Update both the "create new" and "inject into existing" paths in `cmd_setup_plugin()`.

3. **Create `/who` slash command** (`commands/who.md`):
   - New command that runs `claude-switcher status` or a simplified version showing: profile name, email, subscription, rate limits.

4. **Improve auto-switch notification** (`scripts/on-stop-failure.sh`, status line):
   - The status line checks for auto-switch state on every render.
   - Shows "[profile] ⚡ FALLBACK" or similar when on fallback profile.
