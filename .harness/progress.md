# Progress — claude-switcher Iterations

## Iteration 1: Dynamic Rate Limit Reset Tracking (2026-03-30)
- [x] All 7 items complete

## Iteration 2: Fix Auto-Switch + /who Command (2026-03-30)
- [x] All 6 items complete

## Iteration 3: Status-Line-Driven Auto-Switch (2026-03-30)

### Investigation
- Status line runs on every render, has freshest rate limit data from input JSON
- PostToolUse hook is redundant: reads stale file written by status line
- SessionStart hook duplicates switch-back + mismatch detection that status line can do
- StopFailure hook must stay: status line can't see API errors
- Profile indicator is always-on, should be opt-in
- No generic `/cli` command for full CLI access
- Setup is mostly idempotent but dies if status line script missing

### Build
- [x] Create statusline-autoswitch.sh helper (threshold check + switch-back + mismatch detection)
- [x] Remove PostToolUse hook and on-post-tool-use.sh
- [x] Simplify SessionStart hook (info display only)
- [x] Make profile indicator opt-in (show_in_statusline config key)
- [x] Create /cli slash command (commands/cli.md)
- [x] Make setup fully idempotent (helpers always installed, warning not die on missing script)
- [x] Update setup.sh injection for autoswitch helper (3-stage: rate limits, autoswitch, profile)
- [x] Update docs, README, auto-config.md, help text, bump to 3.0.0
