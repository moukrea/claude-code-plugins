# Progress — claude-switcher Iterations

## Iterations 1-3 (2026-03-30)
- [x] All complete and QA passed

## Iteration 4: hooks.json schema + init.sh + README (2026-03-30)

### Investigation
- Cached plugin at ~/.claude/plugins/cache/ has hooks.json without `"hooks"` wrapper key
- Claude Code expects `{"hooks": {"EventName": [...]}}` not `{"EventName": [...]}`
- CLI symlink exists locally but points to dev path, not cache path
- init.sh runs but doesn't install status line helpers

### Build
- [ ] Fix hooks.json schema (add top-level "hooks" wrapper)
- [ ] Make init.sh robust (install helpers, setup-plugin)
- [ ] Rewrite README as comprehensive user guide
