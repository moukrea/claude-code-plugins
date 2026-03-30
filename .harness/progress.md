# Progress — Dynamic Rate Limit Reset Tracking

## Investigation (2026-03-30)
- Read all source files in plugins/claude-switcher/scripts/lib/
- Read session-start.sh, on-post-tool-use.sh, setup.sh
- Checked live rate-limits.json and statusline-command.sh
- Found field name bug: `.percent` vs `.used_percentage`
- Identified 7 changes needed across 6 files
- Created spec

## Build
- [x] Fix field name bug in rate-limits.sh and session-start.sh (.percent → .used_percentage)
- [x] Add per-profile rate limit saving (save_rate_limits_for_active_profile)
- [x] Rewrite auto-state.sh for dynamic resets_at tracking (primary_resets_at + switch_back_at)
- [x] Add switch-back check in check-limits flow (check_primary_reset_and_switch_back)
- [x] Remove deprecated config options from auto-config.sh (daily-reset, weekly-reset)
- [x] Update session-start.sh for new state format (switch_back_at instead of next_reset)
- [x] Update command docs (auto-config.md, help text, completions checked)
