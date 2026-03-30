# Progress — claude-switcher Iterations

## Iteration 1: Dynamic Rate Limit Reset Tracking (2026-03-30)
- [x] Fix field name bug in rate-limits.sh and session-start.sh (.percent → .used_percentage)
- [x] Add per-profile rate limit saving (save_rate_limits_for_active_profile)
- [x] Rewrite auto-state.sh for dynamic resets_at tracking (primary_resets_at + switch_back_at)
- [x] Add switch-back check in check-limits flow (check_primary_reset_and_switch_back)
- [x] Remove deprecated config options from auto-config.sh (daily-reset, weekly-reset)
- [x] Update session-start.sh for new state format (switch_back_at instead of next_reset)
- [x] Update command docs (auto-config.md, help text, completions checked)

## Iteration 2: Fix Auto-Switch + /who Command (2026-03-30)

### Investigation
- Traced full auto-switch flow: PostToolUse → check-limits → do_auto_switch_to_fallback
- Traced StopFailure flow: on-stop-failure.sh → limit-hit → do_auto_switch_to_fallback
- Found StopFailure matcher "rate_limit" is too restrictive — may not match actual Claude Code error types
- Found no notification mechanism — StopFailure output is ignored, PostToolUse is async
- Confirmed rate-limits.json IS being populated by statusline capture (7%, 65% currently)
- Confirmed auto-switch config is correct (enabled, primary=work, fallback=personal, threshold=97%)
- No existing /who command — only /profiles (full table) and /switch

### Build
- [ ] Remove StopFailure matcher from hooks.json
- [ ] Add profile indicator to status line injection (setup.sh)
- [ ] Create /who slash command (commands/who.md)
- [ ] Add fallback alert to status line when on_fallback is true
