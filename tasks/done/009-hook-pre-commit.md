# Task 009: Hook pre-commit.sh Modifications

## Status
done

## Dependencies
- 001-config-schema (uses `get_config()` for `.branch.autoStashOnSwitch`, `.git.protectDefaultBranch`)
- 007-stash-functions (uses `auto_stash()` from `git-utils.sh`, `normalize_protect_default_branch()`)

## Spec References
- spec/05-stash-and-robustness.md (sections 1.7, 3.2-3.6)
- spec/06-hooks-and-lifecycle.md (section 7)

## Scope
Modify the existing `pre-commit.sh` script to add two capabilities: (a) branch switch detection with `is_branch_switch_command()` that triggers `auto_stash()` before allowing the switch, and (b) enhanced protected branch enforcement upgrading the boolean `protectDefaultBranch` to a tri-state (`warn`/`block`/`off`) with backward compatibility.

## Acceptance Criteria
- [x] `is_branch_switch_command()` detects `git checkout <branch>` (without `-b`/`-B`) and `git switch <branch>` (without `-c`/`-C`), sets `SWITCH_TARGET` global variable
- [x] When a branch switch is detected and `branch.autoStashOnSwitch` is `true` and `has_uncommitted_changes`, call `auto_stash()` and emit: `"[git-pilot] Stashed uncommitted changes on '${current_br}' before switching to '${SWITCH_TARGET}'."`
- [x] Branch switch detection block is placed BEFORE the existing `is_git_commit_command` check (early in the main flow)
- [x] All existing `PROTECT_DEFAULT` boolean checks replaced with tri-state: `protect_mode=$(get_config "$CONFIG" '.git.protectDefaultBranch' 'warn')` then `protect_mode=$(normalize_protect_default_branch "$protect_mode")`
- [x] `"block"` mode calls `output_block "[git-pilot] Commits to '${default_br}' are blocked by policy (git.protectDefaultBranch: block). Create a feature branch first using /branch."`
- [x] `"warn"` mode preserves v1 behavior (allow with warning message)
- [x] `"off"` mode emits no message

## Implementation Notes

### Branch switch detection -- add `is_branch_switch_command()` alongside existing `is_branch_creation_command()`

```bash
is_branch_switch_command() {
  local cmd="$1"
  SWITCH_TARGET=""
  # git checkout <branch> (not -b)
  if [[ "$cmd" =~ git[[:space:]]+checkout[[:space:]]+([^-][^[:space:]]+) ]] && \
     ! [[ "$cmd" =~ git[[:space:]]+checkout[[:space:]]+-[bB] ]]; then
    SWITCH_TARGET="${BASH_REMATCH[1]}"
    return 0
  fi
  # git switch <branch> (not -c)
  if [[ "$cmd" =~ git[[:space:]]+switch[[:space:]]+([^-][^[:space:]]+) ]] && \
     ! [[ "$cmd" =~ git[[:space:]]+switch[[:space:]]+-[cC] ]]; then
    SWITCH_TARGET="${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}
```

Known limitation: `git checkout <branch>` vs `git checkout <file>` is ambiguous; the regex checks for absence of `-b` but paths without `--` may be misdetected.

### Branch switch auto-stash trigger -- insert before the `is_git_commit_command` check in the main flow (after config loading, before "--- Branch creation detection ---" section)

```bash
SWITCH_TARGET=""
if is_branch_switch_command "$COMMAND"; then
  auto_stash_cfg=$(get_config "$CONFIG" '.branch.autoStashOnSwitch' 'true')
  if [[ "$auto_stash_cfg" == "true" ]] && has_uncommitted_changes; then
    current_br=$(get_current_branch)
    if auto_stash "$current_br" "$SESSION_ID"; then
      output_allow_with_message "[git-pilot] Stashed uncommitted changes on '${current_br}' before switching to '${SWITCH_TARGET}'."
    fi
  fi
fi
```

### Protected branch tri-state -- replace all three existing boolean protection blocks

There are 3 places in v1 `pre-commit.sh` where `PROTECT_DEFAULT` is checked (lines ~507-514, ~524-531, ~627-633). Replace each with the tri-state pattern:

```bash
protect_mode=$(get_config "$CONFIG" '.git.protectDefaultBranch' 'warn')
protect_mode=$(normalize_protect_default_branch "$protect_mode")
if is_on_default_branch "$CONFIG" 2>/dev/null; then
  default_br=$(get_default_branch "$CONFIG")
  case "$protect_mode" in
    warn)
      SYSTEM_MSG="[git-pilot] Warning: You are committing directly to '${default_br}'. Consider creating a feature branch first."
      ;;
    block)
      output_block "[git-pilot] Commits to '${default_br}' are blocked by policy (git.protectDefaultBranch: block). Create a feature branch first using /branch."
      ;;
    off)
      ;;
  esac
fi
```

Backward compatibility: `true` -> `"warn"`, `false` -> `"off"`, unknown -> `"warn"`. The `normalize_protect_default_branch()` function is implemented in task 007.

## Files to Create or Modify
- plugins/git-pilot/scripts/pre-commit.sh (modify -- add `is_branch_switch_command()`, auto-stash trigger, tri-state protected branch)
