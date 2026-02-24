# Task 001: Config Schema Update

## Status
done

## Dependencies
- None

## Spec References
- spec/01-config-and-state.md

## Scope
Update the plugin defaults config file (`defaults/config.json`) to include all new v2 config keys, and add the `normalize_protect_default_branch()` backward-compatibility function to `config.sh`. The existing three-tier merge logic (`load_config()`, `get_config()`) remains unchanged. This task makes the full v2 config schema available so that all downstream modules can call `get_config()` for new keys and receive correct defaults.

## Acceptance Criteria
- [x] `defaults/config.json` contains the complete v2 schema exactly as specified in spec Section 2, including all new top-level sections (`rebase`, `worktree`, `agentTeams`) and all new keys within existing sections (`git.autoFetch`, `git.fetchRetries`, `git.fetchRetryDelaySec`, `git.protectDefaultBranch` changed from `true` to `"warn"`, `branch.unrelatedWorkDetection`, `branch.autoStashOnSwitch`).
- [x] `config.sh` exports `normalize_protect_default_branch()` with the exact case mapping: `true` -> `"warn"`, `false` -> `"off"`, `warn|block|off` -> pass-through, unknown -> `"warn"`.
- [x] `load_config()` and `get_config()` functions in `config.sh` are unchanged (no modifications to merge logic).
- [x] The existing v1 config file format (with `"protectDefaultBranch": true`) continues to work via the three-tier merge: v1 boolean values are not rejected by `jq`, and callers normalize via `normalize_protect_default_branch()`.
- [x] The JSON in `defaults/config.json` is valid (parseable by `jq .`).

## Implementation Notes

### `defaults/config.json` -- full replacement

Replace the entire file content with the v2 schema from spec Section 2. Key differences from v1:

- `git.protectDefaultBranch`: change from `true` (boolean) to `"warn"` (string)
- Add `git.autoFetch`: `true`
- Add `git.fetchRetries`: `2`
- Add `git.fetchRetryDelaySec`: `3`
- Add `branch.unrelatedWorkDetection`: `true`
- Add `branch.autoStashOnSwitch`: `true`
- Add entire `rebase` section: `{ "autoRebaseBeforePush": true, "conflictStrategy": "prompt", "allowForcePush": "ask" }`
- Add entire `worktree` section: `{ "enabled": true, "basePath": "../{{project}}-worktrees", "cleanupOnMerge": true }`
- Add entire `agentTeams` section: `{ "suppressPromptsForAgents": true, "orchestratorOnly": ["push", "mr"] }`

All existing v1 keys and their values remain unchanged (except `protectDefaultBranch`).

The complete JSON is given verbatim in spec/01-config-and-state.md Section 2. Use it exactly (no JSONC comments in the actual file).

### `config.sh` -- add `normalize_protect_default_branch()`

Append the following function after the existing `get_config()` function:

```bash
normalize_protect_default_branch() {
  local value="$1"
  case "$value" in
    true)  echo "warn" ;;
    false) echo "off" ;;
    warn|block|off) echo "$value" ;;
    *) echo "warn" ;;
  esac
}
```

This function is called by downstream modules wherever `git.protectDefaultBranch` is read, like so:

```bash
raw_value=$(get_config "$config" '.git.protectDefaultBranch' 'warn')
protect_mode=$(normalize_protect_default_branch "$raw_value")
```

The function itself does not call `get_config()` -- it only normalizes a value already retrieved.

### Validation

After editing, confirm the JSON is valid:
```bash
jq . plugins/git-pilot/defaults/config.json
```

## Files to Create or Modify
- plugins/git-pilot/defaults/config.json (modify)
- plugins/git-pilot/scripts/config.sh (modify)
