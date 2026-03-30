# QA Report -- Round 1

## Verdict: FAIL

## Scores
- **Product Depth**: 8/10 (threshold: 6) -- All iteration 3 features implemented with good depth; helpers, injection, idempotency, mismatch detection all present
- **Functionality**: 5/10 (threshold: 7) -- Critical bug: status-line-driven switch-back is broken (reset-state clears original_profile before reading it)
- **Visual Design**: N/A (CLI tool)
- **Code Quality**: 7/10 (threshold: 5) -- Clean structure, proper quoting, good error handling, but the switch-back ordering bug is a logic error that should have been caught by testing

## Tests Performed

### hooks.json validation
- Parsed with `jq .` -- valid JSON
- Verified exactly 2 hook events: SessionStart and StopFailure
- Confirmed PostToolUse is NOT present

### CLI basics
- `version`: returns "claude-switcher 3.0.0" -- correct
- `help`: displays full command list including show-profile subcommand
- `auto-config show`: displays all fields including new "Status line" field

### auto-config show-profile subcommand
- `auto-config show-profile` (no args): shows current value + usage hint
- `auto-config show-profile enable`: sets show_in_statusline=true in auto-switch.json
- `auto-config show-profile disable`: sets show_in_statusline=false
- `auto-config show` includes "Status line:" field

### statusline-autoswitch.sh scenarios
- **Below threshold** (50% 5h, 30% 7d, threshold 97%): No CLI calls spawned -- PASS
- **Above threshold** (98% 5h, threshold 97%): `check-limits` spawned async -- PASS
- **On fallback, past switch_back_at**: Calls reset-state then reads original_profile -- **BUG: reads null because reset-state already cleared it**
- **On fallback, future switch_back_at**: No CLI calls -- PASS
- **Auto-switch disabled** (99% usage): No CLI calls -- PASS

### statusline-profile.sh
- show_in_statusline=false: indicator is empty string -- PASS
- show_in_statusline=true, normal: shows "[work] " -- PASS
- show_in_statusline=true, on fallback: shows "[personal FALLBACK] " -- PASS

### SessionStart hook
- Outputs JSON result with profile info, rate limits, and fallback status
- Does NOT contain switch/mismatch logic (only display)
- Correctly shows switch_back_at time in human-readable format

### on-post-tool-use.sh deletion
- File does not exist at scripts/on-post-tool-use.sh -- PASS

### commands/cli.md
- Valid frontmatter (name, description, argument-hint, allowed-tools)
- Reasonable description and usage examples

### commands/who.md (regression)
- Valid frontmatter, references `~/.claude-switcher/cli status`

### setup-plugin (new status line)
- Creates statusline-command.sh with rate-limit capture, autoswitch sourcing, and profile sourcing
- Creates both helper files (statusline-autoswitch.sh, statusline-profile.sh)
- Idempotent: second run reports "already configured" for all 3 stages, no duplications

### setup-plugin (existing status line)
- Injects 3 stages into existing custom script in correct order
- Idempotent: second run detects markers, skips injection
- Warns gracefully when status line script path not found (does not die)

### End-to-end status line simulation
- Piped JSON through statusline-command.sh: outputs correct format
- rate-limits.json written correctly with both windows
- Profile indicator prepended when enabled
- Auto-switch forward (primary -> fallback) triggered correctly at 99% usage

### Edge cases
- Empty $input: no crash, exit 0
- Malformed JSON input: no crash, exit 0
- Missing rate_limits in JSON: no crash, exit 0
- Missing config files: no crash, empty indicator

### Regression tests
- list, show, use, prev, check-limits, auto-config (all subcommands) -- all working

## Issues Found

### Critical (must fix)

- **Switch-back race condition** (`scripts/lib/setup.sh:168-170`, installed at `~/.claude-switcher/statusline-autoswitch.sh:46-50`):
  The statusline-autoswitch helper calls `reset-state` (which clears `original_profile` to null) BEFORE reading `original_profile` from the state file. This means the status-line-driven switch-back never actually switches back to the primary profile. The switch fails silently.

  **Reproduction**:
  1. Set up auto-switch with primary=work, fallback=personal
  2. Trigger a switch to fallback (active becomes personal)
  3. Set switch_back_at to a past epoch
  4. Source statusline-autoswitch.sh with valid $input
  5. Result: active_profile remains "personal" (should be "work")

  **Fix**: In the HEREDOC template in `_install_autoswitch_helper()`, swap lines 168-170:
  ```sh
  # BEFORE (buggy):
  sh "$cli" auto-config reset-state >/dev/null 2>&1
  local original
  original=$(jq -r '.original_profile // empty' "$state_file" 2>/dev/null)

  # AFTER (correct):
  local original
  original=$(jq -r '.original_profile // empty' "$state_file" 2>/dev/null)
  sh "$cli" auto-config reset-state >/dev/null 2>&1
  ```

  Note: The CLI `check-limits` path (`do_auto_switch_back` in auto-state.sh) does NOT have this bug -- it reads original before clearing. Only the status-line helper is affected. Since the status line is now the PRIMARY switch-back mechanism (SessionStart was simplified per spec), this is a critical functional failure.

### Warning (should fix)

- None

### Note (minor, optional)

- The `cli` md command at `commands/cli.md` has `argument-hint: "<command> [args...]"` which is good UX. No issues.
- The README accurately reflects the new architecture. No stale documentation found.

## Spec Coverage

| Feature | Status | Notes |
|---------|--------|-------|
| statusline-autoswitch.sh helper | ⚠️ Partial | Forward switch works; switch-back has ordering bug (reads original_profile after reset-state clears it) |
| PostToolUse hook removed | ✅ Working | hooks.json has only SessionStart + StopFailure; on-post-tool-use.sh deleted |
| SessionStart simplified | ✅ Working | Info display only, no switch/mismatch logic |
| Profile indicator opt-in | ✅ Working | show_in_statusline defaults false, statusline-profile.sh respects flag |
| /cli slash command | ✅ Working | Valid frontmatter, reasonable description, generic passthrough |
| Setup idempotency | ✅ Working | _inject_into_statusline handles 3 stages, markers prevent duplication, warns on missing script |
| auto-config show-profile subcommand | ✅ Working | enable/disable/show all work, persisted in auto-switch.json |
| Version 3.0.0 | ✅ Working | vars.sh, plugin.json both show 3.0.0 |
| Profile mismatch detection (moved to status line) | ✅ Working | Tested with mismatched email, auto-corrects config.json |
| auto-config show displays Status line field | ✅ Working | Shows show_in_statusline value |
| Async spawns (non-blocking) | ✅ Working | check-limits spawned with &, use spawned in subshell with & |
| Edge case handling | ✅ Working | Empty input, malformed JSON, missing files all handled gracefully |

## Feedback for Builder

The only blocking issue is the switch-back ordering bug in `scripts/lib/setup.sh` lines 168-170 (the `_install_autoswitch_helper` HEREDOC). The `reset-state` call must come AFTER reading `original_profile`, not before. This is a one-line reorder fix.

After fixing the template in setup.sh, remember that running `setup-plugin` will reinstall the helper, so existing installations will get the fix on next setup.

Everything else in iteration 3 is solid: the architectural simplification is clean, setup idempotency works well, the profile indicator is properly opt-in, and all the new subcommands function correctly.
