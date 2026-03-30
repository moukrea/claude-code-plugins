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
- [ ] Create statusline-autoswitch.sh helper (threshold check + switch-back + mismatch detection)
- [ ] Remove PostToolUse hook and on-post-tool-use.sh
- [ ] Simplify SessionStart hook (info display only)
- [ ] Make profile indicator opt-in (show_in_statusline config key)
- [ ] Create /cli slash command
- [ ] Make setup fully idempotent
- [ ] Update setup.sh injection for autoswitch helper
- [ ] Update docs and bump to 3.0.0
