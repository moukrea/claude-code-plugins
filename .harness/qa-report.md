# QA Report — Round 4

## Verdict: PASS

## Scores
- **Product Depth**: 8/10 (threshold: 6) — All features from spec fully implemented across 4 iterations; hooks schema, init robustness, and README completeness all addressed
- **Functionality**: 8/10 (threshold: 7) — CLI works end-to-end, hooks.json validates correctly, init.sh runs from any path, all commands tested
- **Visual Design**: N/A (CLI plugin)
- **Code Quality**: 7/10 (threshold: 5) — Clean shell scripts, proper error handling, set -eu, atomic file writes, good separation of concerns

## Tests Performed

1. **hooks.json schema validation**:
   - Parsed with Python JSON + assertions: verified top-level `"hooks"` wrapper key exists
   - Verified `SessionStart` and `StopFailure` events are present as arrays of matcher objects
   - Verified each matcher object contains a `"hooks"` array with `type` and `command` fields
   - Verified no `"matcher"` key on `StopFailure` (removed per iteration 2 spec)
   - Verified no `PostToolUse` event (removed per iteration 3 spec)
   - Pretty-printed with `jq .` to verify well-formed JSON

2. **plugin.json validation**:
   - Confirmed `"hooks": "./hooks/hooks.json"` resolves to existing file from plugin root
   - Confirmed version 3.0.0

3. **init.sh testing**:
   - Ran from plugin directory: all sections pass (Prerequisites, Smoke test, CLI symlink, Status line helpers)
   - Ran from `/tmp` (different directory): resolves PLUGIN_ROOT correctly via `$(cd "$(dirname "$0")" && pwd)`, all sections pass
   - Verified `~/.claude-switcher/cli` symlink created and points to correct target
   - Verified `setup-plugin` runs automatically and completes
   - Verified jq dependency check with helpful install instructions per platform
   - Verified error handling when scripts not found (tested by code inspection)

4. **CLI regression testing**:
   - `cli version`: outputs "claude-switcher 3.0.0"
   - `cli help`: complete help with all commands listed
   - `cli status`: shows active profile, auto-switch state, rate limits, live auth
   - `cli list`: shows all profiles with formatting
   - `cli show work`: shows detailed profile info
   - `cli auto-config show`: shows config with dynamic reset timestamps
   - `cli auto-config` (no args): same as show (default)
   - `cli nonexistent-command`: proper error message + exit code 1

5. **README verification**:
   - Automated 23-point check covering all required topics (all passed):
     - Install section, save/switch profiles, auto-switch setup (primary, fallback, threshold)
     - Status line indicator (opt-in via show-profile), /who, /cli passthrough
     - All slash commands documented, StopFailure safety net, How It Works section
     - jq dependency, profile storage explanation, uninstall
   - Manual review confirmed:
     - Step-by-step getting started guide
     - Auto-config subcommands table
     - CLI commands via `/cli` table
     - Architecture description accurate (status line driven + StopFailure safety net)
     - Security mention (chmod 700/600, atomic writes, no network calls)

6. **Field name bug fix verification**:
   - Confirmed `rate-limits.sh` uses `.five_hour.used_percentage` (not `.percent`)
   - Confirmed `session-start.sh` uses `.five_hour.used_percentage` (not `.percent`)

7. **Deprecated field cleanup verification**:
   - Grepped for `daily_reset|weekly_reset` -- only found in migration code that removes them (correct)

## Issues Found

### Critical (must fix)
None.

### Warning (should fix)
None.

### Note (minor, optional)
- `init.sh` line 28: smoke test runs `sh "$PLUGIN_ROOT/scripts/claude-switcher.sh" help >/dev/null 2>&1` which swallows errors. If `help` partially fails, user only sees "CLI: warning, help failed" without details. Consider showing stderr.
- README mentions `claude mcp` for install but this is a plugin manager command, not a standard claude CLI command. This may confuse users if the plugin marketplace doesn't exist yet.

## Spec Coverage

| Feature | Status | Notes |
|---------|--------|-------|
| Fix hooks.json schema (top-level `"hooks"` wrapper) | ✅ Working | Validated: `{"hooks": {"SessionStart": [...], "StopFailure": [...]}}` |
| Make init.sh robust (any path, setup-plugin auto) | ✅ Working | Tested from plugin dir and /tmp; both succeed |
| init.sh creates ~/.claude-switcher directory | ✅ Working | `mkdir -p` on line 35 |
| init.sh creates CLI symlink | ✅ Working | Verified symlink exists and works |
| init.sh runs setup-plugin automatically | ✅ Working | Helper installation confirmed |
| init.sh jq dependency check | ✅ Working | With platform-specific install hints |
| README: install instructions | ✅ Working | Clear section with manual alternative |
| README: save profiles | ✅ Working | Step-by-step guide |
| README: switch profiles | ✅ Working | Including `prev` shortcut |
| README: auto-switch setup | ✅ Working | enable, primary, fallback, threshold |
| README: status line indicator (opt-in) | ✅ Working | show-profile enable/disable documented |
| README: all slash commands listed | ✅ Working | Table with 8 commands |
| README: /cli passthrough documented | ✅ Working | With common command examples |
| README: /who documented | ✅ Working | In both getting started and commands table |
| README: How it works section | ✅ Working | Accurate architecture description |
| README: status line driven + StopFailure safety net | ✅ Working | Both described correctly |
| plugin.json hooks reference valid | ✅ Working | `"hooks": "./hooks/hooks.json"` resolves |
| No regressions (CLI commands) | ✅ Working | version, help, status, list, show, auto-config all work |
| No regressions (field name bug fix) | ✅ Working | `used_percentage` confirmed in rate-limits.sh and session-start.sh |
| No regressions (PostToolUse removed) | ✅ Working | Not in hooks.json, script file deleted |
| No regressions (StopFailure no matcher) | ✅ Working | No `"matcher"` key in StopFailure hook entry |

## Feedback for Builder

All iteration 4 changes are correctly implemented. The hooks.json schema fix resolves the "Invalid input: expected record, received undefined" error. init.sh is robust and works from any path. The README is comprehensive and accurate.

The plugin is in good shape across all 4 iterations.
