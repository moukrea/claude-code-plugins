# QA Report -- Round 2

## Verdict: PASS

## Scores
- **Product Depth**: 9/10 (threshold: 6) -- All iteration 2 features fully implemented with thoughtful edge case handling (missing config, missing state file).
- **Functionality**: 9/10 (threshold: 7) -- Every feature works correctly when tested with real inputs including edge cases. No bugs found.
- **Visual Design**: N/A (CLI tool)
- **Code Quality**: 8/10 (threshold: 5) -- Clean, consistent shell code. Proper quoting, heredoc usage, error suppression with 2>/dev/null. Good separation of concerns with the helper script pattern.

## Tests Performed

### hooks.json validation
- Validated JSON with `jq .` -- valid
- Confirmed StopFailure hook entry exists with no `matcher` field at either the event level or individual hook level
- Verified all three hook types (SessionStart, PostToolUse, StopFailure) use correct schema: array of objects with `hooks` arrays

### on-stop-failure.sh rate limit detection
- Syntax check: `bash -n` passes
- Tested with non-rate-limit error (`{"error": "some random error"}`) -- exits silently (correct)
- Tested with `rate_limit` string -- triggers fallback switch (correct)
- Tested with `429 Too Many Requests` -- triggers fallback switch (correct)
- Tested with `server overloaded` -- triggers fallback switch (correct)
- Script correctly reads from stdin, checks auto-switch config, and only proceeds for rate-limit-like errors

### commands/who.md
- Validated frontmatter: has `name: who`, `description`, `allowed-tools: Bash`
- Compared with other command files -- follows same pattern (no argument-hint needed since it takes no args)
- Verified the CLI path `~/.claude-switcher/cli status` resolves via symlink to the correct script
- Ran the command -- outputs profile name, email, subscription, rate limits, and fallback status

### statusline-profile.sh helper
- Sourced the helper in normal state -- outputs `[personal] ` (correct)
- Set `on_fallback: true` in auto-switch-state.json, sourced helper -- outputs `[personal FALLBACK] ` (correct)
- Tested with missing config.json -- outputs empty string (graceful degradation)
- Tested with missing auto-switch-state.json -- outputs `[personal] ` (correct, no false FALLBACK)
- File permissions: 644 (read-only, correct for a sourced script)

### setup.sh
- `bash -n` syntax check passes
- Tested `_install_profile_helper()` by deleting the helper, calling the function, and diffing -- creates identical file
- Reviewed "create new" path: calls `_install_profile_helper()`, creates statusline with profile indicator sourced, uses `${_cs_indicator}` in output
- Reviewed "inject into existing" path: awk injection places profile indicator after rate-limit snippet, uses `index()` for robust matching
- Both paths handle idempotency (grep for marker before injecting)

### Live statusline integration
- Piped mock JSON through `~/.claude/statusline-command.sh` -- output starts with `[personal]` in purple ANSI color
- The statusline correctly sources the profile helper and prefixes the output

### No regressions
- `claude-switcher version` -- outputs `2.2.0`
- `claude-switcher help` -- complete help text
- `claude-switcher list` -- shows both profiles correctly
- `claude-switcher status` -- shows active profile, auto-switch config, live auth
- `claude-switcher auto-config show` -- shows config with rate limits and reset times
- `claude-switcher show personal` -- profile details
- `claude-switcher show nonexistent` -- proper error message, exit 1
- `claude-switcher bogus-command` -- proper error message, exit 1
- All 13 shell scripts pass `bash -n` syntax check

### Version consistency
- `vars.sh`: VERSION="2.2.0"
- `plugin.json`: "version": "2.2.0"
- CLI output: "claude-switcher 2.2.0"

## Issues Found

### Critical (must fix)
None.

### Warning (should fix)
None.

### Note (minor, optional)
- The `_install_profile_helper()` hardcodes `~/.claude-switcher/` paths in the generated helper script rather than using `$SWITCHER_DIR`. This is fine since the SWITCHER_DIR is always `~/.claude-switcher`, but if that ever changes the helper would need updating too. Very minor.

## Spec Coverage

| Feature | Status | Notes |
|---------|--------|-------|
| Remove StopFailure matcher | Working | No matcher field in hooks.json. Script handles detection internally. |
| on-stop-failure.sh internal detection | Working | Detects rate_limit, 429, overloaded, usage_limit, too many, quota, throttl, capacity via grep patterns on error fields and transcript |
| /who slash command | Working | Valid frontmatter, correct CLI path, outputs all required info |
| Profile indicator in status line | Working | Shows `[profile]` normally, `[profile FALLBACK]` when on fallback |
| statusline-profile.sh helper | Working | Created by _install_profile_helper(), sourced by statusline, handles missing files gracefully |
| setup.sh "create new" path | Working | Creates statusline with profile indicator integrated |
| setup.sh "inject into existing" path | Working | Awk injection after rate-limit snippet, idempotent with marker check |
| Version bump to 2.2.0 | Working | Consistent across vars.sh, plugin.json, CLI output |
| README updated | Working | Documents /who command and profile indicator/FALLBACK behavior |

## Feedback for Builder

All iteration 2 changes are solid. The implementation is clean and well-tested:

1. The decision to remove the StopFailure matcher and rely on the script's own detection is correct -- the script's grep patterns cover many more error string variants than a single matcher could.

2. The profile helper as a separate sourced file is a good architectural choice -- it keeps the statusline script clean and makes the helper independently testable and updatable.

3. Edge case handling is thorough: missing config.json returns empty indicator, missing state file defaults to non-fallback, and the setup injection is idempotent.

No changes needed. Ship it.
