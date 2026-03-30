# Progress — Dynamic Rate Limit Reset Tracking

## Investigation (2026-03-30)
- Read all source files in plugins/claude-switcher/scripts/lib/
- Read session-start.sh, on-post-tool-use.sh, setup.sh
- Checked live rate-limits.json and statusline-command.sh
- Found field name bug: `.percent` vs `.used_percentage`
- Identified 7 changes needed across 6 files
- Created spec

## Build
- [ ] Fix field name bug in rate-limits.sh and session-start.sh
- [ ] Add per-profile rate limit saving
- [ ] Rewrite auto-state.sh for dynamic resets_at tracking
- [ ] Add switch-back check in check-limits flow
- [ ] Remove deprecated config options from auto-config.sh
- [ ] Update session-start.sh for new state format
- [ ] Update command docs
