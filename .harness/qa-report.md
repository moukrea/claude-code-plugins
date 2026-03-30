# QA Report -- Round 1

## Verdict: FAIL

## Scores
- **Product Depth**: 8/10 (threshold: 6) -- All spec features implemented with proper edge case handling; per-profile tracking, dynamic resets, migration all work
- **Functionality**: 7/10 (threshold: 7) -- Core flows work correctly but status.sh has a stale reference to removed field, and README documents deprecated commands as current
- **Visual Design**: N/A -- CLI tool
- **Code Quality**: 7/10 (threshold: 5) -- Clean bash, good error handling, atomic writes, proper chmod; two files were missed during the update sweep

## Tests Performed

1. **CLI help and version**: Ran `~/.claude-switcher/cli help` and `version` -- both work correctly. Help text lists valid subcommands without deprecated ones.

2. **auto-config show**: Ran `~/.claude-switcher/cli auto-config show` -- displays enabled status, primary, fallbacks, threshold, rate limits with `used_percentage` values (32%, 62%), and resets_at timestamps formatted correctly.

3. **Deprecated subcommands rejected**: Tested `auto-config daily-reset 15:00` and `auto-config weekly-reset monday` -- both correctly error with "unknown auto-config subcommand" and list valid options. Exit code 1.

4. **Bug fix verification (.percent -> .used_percentage)**: Created a rate-limits.json with old `.percent` field name (no `.used_percentage`). Ran `check-limits` -- correctly read 0 (the jq fallback) and did NOT trigger a switch. Confirms the fix is working.

5. **Per-profile rate limit tracking**: Ran `check-limits` and verified that `~/.claude-switcher/profiles/work/rate-limits.json` was created as a copy of the global rate-limits.json.

6. **Preemptive switch (5h only above threshold)**: Set 5h to 98%, 7d to 62%. Ran `check-limits` -- correctly switched to "personal" fallback. State has `switch_back_at` equal to `five_hour.resets_at` (correct: only 5h was above threshold).

7. **Preemptive switch (both above threshold)**: Set both 5h=99% and 7d=98%. Ran `check-limits` -- `switch_back_at` correctly equals `seven_day.resets_at` (the max of both, since both were above threshold).

8. **Switch-back via check-limits (PostToolUse path)**: While on fallback, set `switch_back_at` to past epoch. Ran `check-limits` -- correctly switched back to "work" and cleared state. This validates spec item 4.

9. **auto-config show on fallback**: While on fallback, ran `auto-config show` -- correctly displays "ON FALLBACK" block with original profile, reason, and formatted switch-back time.

10. **session-start hook (normal)**: Ran session-start.sh -- outputs correct JSON with `used_percentage` values in usage message.

11. **session-start hook (on fallback, future reset)**: Set fallback state with future switch_back_at. Session-start correctly shows fallback message with human-readable switch-back time.

12. **session-start hook (switch-back)**: Set fallback state with past switch_back_at. Session-start correctly auto-switched back to "work" with "(auto-switched back from fallback -- limit reset)" message. State was cleared.

13. **session-start with null switch_back_at**: Set fallback state with null switch_back_at. Session-start correctly shows "switches back: unknown".

14. **Config migration**: Added deprecated fields (`daily_reset_time`, `daily_reset_timezone`, `weekly_reset_day`, `weekly_reset_time`, `estimated_daily_capacity`) to auto-switch.json. Ran `auto-config show` -- all deprecated fields removed, `preemptive_switch_percent` preserved.

15. **Threshold validation**: Tested `threshold 0`, `threshold 101`, `threshold abc`, `threshold` (no arg) -- all correctly rejected with appropriate error messages.

16. **limit-hit with missing resets_at**: Created rate-limits.json without `resets_at` fields. `limit-hit` correctly switches with null `switch_back_at` -- graceful degradation.

17. **is_past_reset_time function**: Tested with past epoch (returns true), future epoch (returns false), null (returns false) -- all correct.

18. **PostToolUse hook**: Ran `on-post-tool-use.sh` directly -- exits cleanly, calls check-limits.

19. **Stale reference scan**: Grepped for `.percent`, `next_reset`, `daily-reset`, `weekly-reset`, `compute_next_reset` across all plugin files.

20. **format_resets_at edge cases**: Tested with empty string (returns "(unknown)"), valid epoch, and epoch with timezone parameter -- all correct.

## Issues Found

### Critical (must fix)

1. **status.sh:41 references removed `next_reset` field** -- `scripts/lib/status.sh` line 41 reads `get_auto_switch_state "next_reset"` but the state JSON no longer has a `next_reset` field (replaced by `switch_back_at`). When on fallback, the `status` command always shows `Next reset: (unknown)` even though `switch_back_at` data exists. Fix: change line 41 to read `switch_back_at` and use `format_resets_at` to display it. Also update the label from "Next reset" to "Switches back" for consistency with auto-config show.

### Warning (should fix)

2. **README.md still documents deprecated commands** -- Three locations reference removed functionality:
   - Line 35: Quick Start step 9 says `/auto-config daily-reset 15:00 Europe/Paris`
   - Lines 72-73: Configuration table lists `/auto-config daily-reset` and `/auto-config weekly-reset`
   - Line 114: "Time-based switch-back" description says "checks if the configured daily reset time has passed" -- should describe dynamic `resets_at` behavior

### Note (minor, optional)

3. **vars.sh shows VERSION="2.0.0" but plugin.json shows "2.1.0"** -- The `version` command outputs "claude-switcher 2.0.0" but the plugin manifest declares 2.1.0. Should be consistent.

## Spec Coverage

| Feature | Status | Notes |
|---------|--------|-------|
| Fix .percent -> .used_percentage in rate-limits.sh | Working | Lines 7, 15 correctly use `.used_percentage` |
| Fix .percent -> .used_percentage in session-start.sh | Working | Lines 122-123 correctly use `.used_percentage` |
| Per-profile rate limit tracking (save_rate_limits_for_active_profile) | Working | Copies to profiles/<name>/rate-limits.json on every check |
| Dynamic reset detection (primary_resets_at + switch_back_at) | Working | State JSON stores both; switch_back_at computed as max of above-threshold windows |
| Replace compute_next_reset with resets_at logic | Working | No compute_next_reset function exists; logic inline in check_rate_limits_and_switch |
| Remove next_reset field from state | Partial | State JSON uses switch_back_at correctly, but status.sh:41 still reads next_reset |
| Config migration removes deprecated fields | Working | Tested: all 5 deprecated fields removed on init |
| Switch-back check in check-limits (PostToolUse path) | Working | check_primary_reset_and_switch_back called when on fallback |
| Remove daily-reset subcommand | Working | Correctly errors with unknown subcommand |
| Remove weekly-reset subcommand | Working | Correctly errors with unknown subcommand |
| Update show subcommand for dynamic resets | Working | Shows resets_at timestamps, fallback status with switch-back time |
| Update default config (no deprecated fields) | Working | New config template has only 4 fields |
| Update session-start switch-back logic | Working | Uses switch_back_at from state |
| Update session-start status messages | Working | Shows human-readable switch-back time |
| Update auto-config.md command doc | Working | No deprecated references; documents dynamic behavior |
| Update README | Broken | Still documents daily-reset and weekly-reset commands |
| Update help text | Working | No deprecated subcommands listed |

## Feedback for Builder

The core implementation is solid -- all the major functional changes work correctly. Two files were missed during the update sweep:

**Priority 1 (Critical):** Fix `scripts/lib/status.sh` line 41. Change:
```
next=$(get_auto_switch_state "next_reset")
```
to:
```
next=$(get_auto_switch_state "switch_back_at")
```
And update the display on line 43 to use `format_resets_at "$next"` and change the label from "Next reset" to "Switches back" for consistency with auto-config show.

**Priority 2 (Warning):** Update `README.md`:
- Remove Quick Start step 9 (line 35) or replace with a note that switch-back is automatic
- Remove rows for daily-reset and weekly-reset from the configuration table (lines 72-73)
- Update the "Time-based switch-back" description (line 114) to reference dynamic resets_at timestamps

**Priority 3 (Note):** Sync VERSION in `scripts/lib/vars.sh` (currently "2.0.0") with plugin.json (currently "2.1.0").
