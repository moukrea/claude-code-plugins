# QA Report — Round 2

## Verdict: PASS

## Scores
- **Product Depth**: 9/10 (threshold: 6) — All 7 spec items fully implemented with migration logic, edge case handling, and consistent patterns across all files
- **Functionality**: 9/10 (threshold: 7) — Every tested flow works correctly: preemptive switching, switch-back via check-limits and session-start, per-profile rate limit saving, config migration, deprecated command rejection
- **Visual Design**: N/A — CLI tool
- **Code Quality**: 8/10 (threshold: 5) — Well-structured library modules, atomic writes with temp files, proper error handling, consistent use of jq, good separation of concerns

## Tests Performed

All tests run against the real CLI (`plugins/claude-switcher/scripts/claude-switcher.sh`) using isolated `$HOME` directories with simulated Claude auth state.

### Code Verification
1. Grepped entire plugin for `next_reset` — 0 matches (confirmed removed)
2. Grepped entire plugin for `.percent` (without `age` suffix) — 0 matches (confirmed fixed)
3. Grepped for `daily-reset` and `weekly-reset` across all files — 0 matches except migration code in auto-state.sh (correct)
4. Verified `used_percentage` appears in exactly 4 correct locations: rate-limits.sh:7, rate-limits.sh:15, session-start.sh:122, session-start.sh:123

### CLI Functional Tests
5. `help` — shows usage, no deprecated commands mentioned
6. `save work --force` — saves profile with correct metadata
7. `save personal --force` — saves second profile
8. `list` — shows both profiles with correct metadata
9. `use work` — switches credentials (verified token changed in .credentials.json)
10. `auto-config enable` / `disable` — toggles correctly
11. `auto-config primary work` — sets primary profile
12. `auto-config fallback personal` — adds fallback profile
13. `auto-config threshold 95` — sets threshold
14. `auto-config show` — displays all config including rate limits and resets_at timestamps
15. `auto-config daily-reset` — correctly rejected as unknown subcommand
16. `auto-config weekly-reset` — correctly rejected as unknown subcommand

### Rate Limit Reading (Spec Item 1)
17. Created rate-limits.json with `used_percentage` field (75% 5h, 40% 7d)
18. `auto-config show` correctly reads and displays "5h: 75%, 7d: 40%"
19. Resets_at timestamps displayed as human-readable dates

### Preemptive Switch (Spec Items 1, 3, 4)
20. Set 5h to 98% (above 95% threshold), 7d to 50% (below)
21. `check-limits` triggered switch to fallback — confirmed `on_fallback=true`
22. State file uses `switch_back_at` (not `next_reset`) — value is 1711900000 (five_hour resets_at, the only window above threshold)
23. `primary_resets_at` stored with both five_hour and seven_day epoch timestamps

### Both Windows Above Threshold (Spec Item 3)
24. Set both 5h (98%) and 7d (99%) above threshold with different resets_at values
25. `switch_back_at` correctly set to max (1712400000 = seven_day), confirming "max of all windows above threshold" logic

### Per-Profile Rate Limit Saving (Spec Item 2)
26. After preemptive switch, `profiles/work/rate-limits.json` exists
27. Contains correct data (used_percentage: 98 for five_hour)

### Check-Limits Switch-Back (Spec Item 4)
28. Set `switch_back_at` to past epoch while on fallback
29. `check-limits` auto-switched back — confirmed `on_fallback=false`

### Config Migration (Spec Item 5)
30. Injected deprecated fields (`daily_reset_time`, `daily_reset_timezone`, `weekly_reset_day`, `weekly_reset_time`)
31. After `auto-config show`, all deprecated fields removed from config file

### Session-Start (Spec Item 6)
32. On fallback with future `switch_back_at` — session-start shows "on fallback" message with switch-back time
33. On fallback with past `switch_back_at` — session-start auto-switches back, shows "auto-switched back from fallback"
34. Normal (not on fallback) — session-start shows rate limit percentages from `used_percentage`

### Limit-Hit Command
35. `limit-hit` with resets_at timestamps — switch_back_at set to earliest (five_hour: 1711900000)

### Status Command
36. While on fallback — shows "ON FALLBACK" with reason and "Switches back" with formatted date via `format_resets_at()`

### Edge Cases
37. `format_resets_at ""` — returns "(unknown)" as expected
38. State file confirmed to have no `next_reset` field (has("next_reset") = false)

## Issues Found

### Critical (must fix)
None.

### Warning (should fix)
None.

### Note (minor, optional)
- `save_rate_limits_for_active_profile()` at rate-limits.sh:49 uses `cp` without `chmod 600` on the destination. The per-profile rate-limits.json inherits source permissions (could be 644). Not a security risk since the parent directory is chmod 700, but inconsistent with the rest of the codebase which explicitly sets 600 on credential files.

## Spec Coverage

| Feature | Status | Notes |
|---------|--------|-------|
| 1. Fix field name bug (`.percent` to `.used_percentage`) | Working | rate-limits.sh:7,15 and session-start.sh:122-123 all read `.used_percentage` |
| 2. Per-profile rate limit tracking | Working | `save_rate_limits_for_active_profile()` copies to `profiles/<name>/rate-limits.json` on every check |
| 3. Dynamic reset detection (`primary_resets_at` + `switch_back_at`) | Working | State stores both `primary_resets_at` object and computed `switch_back_at`. Uses max of above-threshold windows |
| 4. Switch-back check in check-limits (async path) | Working | `check_primary_reset_and_switch_back()` reads `switch_back_at`, compares to now, calls `do_auto_switch_back` |
| 5. Remove deprecated config options | Working | `daily-reset` and `weekly-reset` rejected. Migration removes deprecated fields. Default config clean |
| 6. Update session-start.sh | Working | Uses `switch_back_at` (not `next_reset`), reads `used_percentage`, formats switch-back as human-readable |
| 7. Update command docs (auto-config.md) | Working | No daily-reset/weekly-reset docs. Documents dynamic reset behavior |

## Feedback for Builder

All 7 spec items verified working. Both round-1 issues (status.sh `next_reset` and README deprecated commands) confirmed fixed. No regressions found.

Optional improvement: add `chmod 600` after the `cp` in `save_rate_limits_for_active_profile()` for consistency with the rest of the security model.
