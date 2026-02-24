# Module 05: Stash Management, Detached HEAD Recovery & Protected Branch Enhancement

## Cross-References

- **Depends on `01-config-and-state.md`**: for config schema (three-tier merge via `load_config()`, `get_config()` accessor), session state schema (`/tmp/git-pilot-${SESSION_ID}.json`), and state read/write functions (`get_state_file()`, `read_state()`, `update_state()`, `write_state()` with atomic temp-file + `mv`).
- **Depends on `02-git-utils-and-network.md`**: for `get_current_branch()`, `has_uncommitted_changes()`, `is_on_default_branch()`, `get_default_branch()`, and `is_git_repo()` utility functions in `scripts/git-utils.sh`.
- **Depends on `04-agent-and-worktree.md`**: the auto-stash prompt suppression in agent context uses `is_agent_context()` from `scripts/agent.sh`.

---

## 1. Stash Management (spec section 4.7)

### 1.1 Modified Library File

**Modified file**: `scripts/git-utils.sh`

### 1.2 Config and State

Config: `branch.autoStashOnSwitch` (boolean, default `true`) -- auto-stash uncommitted changes on branch switch.

State: `stashRefs` (array of `{ref, branch, message, createdAt}`) -- tracks stashes created by git-pilot. Example entry: `{"ref":"stash@{0}", "branch":"feat/add-dark-mode", "message":"git-pilot auto-stash on feat/add-dark-mode", "createdAt":"2026-02-24T20:00:00Z"}`.

### 1.3 Auto-stash on Branch Switch

Triggered when `branch.autoStashOnSwitch` is `true` and a branch switch is detected in `pre-commit.sh`.

```bash
# In git-utils.sh
auto_stash() {
  local current_branch="$1"
  local session_id="$2"

  if ! has_uncommitted_changes; then
    return 1  # Nothing to stash
  fi

  local stash_msg="git-pilot auto-stash on ${current_branch}"
  if git stash push -m "$stash_msg" >/dev/null 2>&1; then
    local stash_ref
    stash_ref=$(git stash list --format='%gd' | head -1)

    # Record in session state
    if [[ -n "$session_id" ]]; then
      local state_file
      state_file=$(get_state_file "$session_id")
      update_state "$state_file" \
        --arg ref "$stash_ref" \
        --arg branch "$current_branch" \
        --arg msg "$stash_msg" \
        '.stashRefs += [{ref: $ref, branch: $branch, message: $msg, createdAt: (now | todate)}]'
    fi

    return 0
  fi

  return 1
}
```

Stash message format: `"git-pilot auto-stash on ${current_branch}"`. The ref is captured from `git stash list --format='%gd' | head -1` immediately after push and recorded in session state.

### 1.5 Auto-restore on Branch Switch

When switching back to a branch that had changes stashed:

```bash
auto_restore_stash() {
  local target_branch="$1"
  local session_id="$2"

  if [[ -z "$session_id" ]]; then
    return 1
  fi

  local state_file
  state_file=$(get_state_file "$session_id")
  local state
  state=$(read_state "$state_file")

  # Find stash for this branch
  local stash_ref
  stash_ref=$(echo "$state" | jq -r \
    --arg branch "$target_branch" \
    '.stashRefs[] | select(.branch == $branch) | .ref' | head -1)

  if [[ -z "$stash_ref" ]] || [[ "$stash_ref" == "null" ]]; then
    return 1  # No stash for this branch
  fi

  # Find the stash index by message
  local stash_msg
  stash_msg=$(echo "$state" | jq -r \
    --arg branch "$target_branch" \
    '.stashRefs[] | select(.branch == $branch) | .message' | head -1)

  local stash_index
  stash_index=$(git stash list --format='%gd %s' | grep "$stash_msg" | head -1 | cut -d' ' -f1)

  if [[ -n "$stash_index" ]]; then
    if git stash pop "$stash_index" >/dev/null 2>&1; then
      # Remove from state
      update_state "$state_file" \
        --arg branch "$target_branch" \
        '.stashRefs = [.stashRefs[] | select(.branch != $branch)]'
      return 0
    fi
  fi

  return 1
}
```

Lookup uses jq to find the stash ref/message by branch, then `git stash list` grep to find the current index. On successful pop, the entry is removed from state. Known limitation: stash-by-message lookup is fragile if the user manually creates stashes with a similar `"git-pilot auto-stash on "` prefix.

### 1.6 Stash Messages

| Event | Message |
|-------|---------|
| Auto-stash on switch | `"[git-pilot] Stashed uncommitted changes on '${current_br}' before switching to '${SWITCH_TARGET}'."` |
| Auto-restore on return | `"[git-pilot] Restored stashed changes on '${branch}'."` |
| Restore failed (conflicts) | `"[git-pilot] Could not auto-restore stash on '${branch}' — conflicts detected. Run 'git stash pop' manually to resolve."` |

### 1.7 Branch Switch Detection in `pre-commit.sh`

The auto-stash is triggered from `pre-commit.sh` when a branch switch command is detected:

```bash
# In the branch creation detection section, add branch switch detection:
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

# Before existing commit detection:
SWITCH_TARGET=""
if is_branch_switch_command "$COMMAND"; then
  auto_stash=$(get_config "$CONFIG" '.branch.autoStashOnSwitch' 'true')
  if [[ "$auto_stash" == "true" ]] && has_uncommitted_changes; then
    current_br=$(get_current_branch)
    if auto_stash "$current_br" "$SESSION_ID"; then
      output_allow_with_message "[git-pilot] Stashed uncommitted changes on '${current_br}' before switching to '${SWITCH_TARGET}'."
    fi
  fi
fi
```

Known limitation: `git checkout <branch>` vs. `git checkout <file>` is ambiguous; the regex checks for absence of `-b` but paths without `--` may be misdetected.

### 1.8 CLAUDE.md Behavioral Rule (Rule 8)

```markdown
## Rule 8: Branch switching

When switching branches (via /branch, user request, or unrelated work detection):

1. If there are uncommitted changes and `branch.autoStashOnSwitch` is `true`, stash
   them automatically before switching. Inform the user: "Stashed changes on '<branch>'."
2. After switching, check if there's a git-pilot stash for the target branch and
   restore it automatically.
3. If stash restoration fails (conflicts), inform the user and suggest manual resolution.
```

### 1.9 Invariant: Never Lose Stash Data

Stash operations that fail MUST NOT lose data. Use `stash apply` before `stash drop` in manual workflows. The `auto_restore_stash` function uses `git stash pop` which applies and drops atomically; if the apply fails (conflicts), the stash is preserved.

### 1.10 Test Scenarios

- Auto-stash on branch switch -> changes stashed, message emitted.
- Auto-restore on return -> stash popped, message emitted.
- Restore fails -> warning with manual instructions.

---

## 2. Detached HEAD Recovery (spec section 4.8)

### 2.1 Trigger

`session-start.sh`, when `get_current_branch` returns empty (no current branch).

### 2.2 Detection and Recovery Logic

```bash
# In session-start.sh
current_branch=$(get_current_branch)

if [[ -z "$current_branch" ]]; then
  # Detached HEAD
  local head_sha
  head_sha=$(git rev-parse --short HEAD 2>/dev/null)

  # Try to find what branch we were on
  local prev_branch
  prev_branch=$(git reflog show --format='%gs' | grep -m1 'checkout: moving from' | \
    sed 's/checkout: moving from \([^ ]*\) to .*/\1/')

  if [[ -n "$prev_branch" ]]; then
    messages+=("[git-pilot] Detached HEAD at ${head_sha}. Previous branch was '${prev_branch}'. Prompt the user: return to '${prev_branch}', create a new branch from HEAD, or continue in detached state.")
  else
    messages+=("[git-pilot] Detached HEAD at ${head_sha}. Prompt the user: create a new branch from HEAD or continue in detached state.")
  fi
fi
```

Previous branch lookup uses reflog. If found: three options (return, new branch, continue detached). If not found: two options (new branch, continue detached).

---

## 3. Protected Branch Enhancement (spec section 4.9)

### 3.1 Modified File

**Modified file**: `scripts/pre-commit.sh`

### 3.2 Relevant Config Key

From `defaults/config.json`:

```jsonc
{
  "git": {
    "protectDefaultBranch": "warn"
  }
}
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `git.protectDefaultBranch` | string | `"warn"` | `"warn"` / `"block"` / `"off"` -- was boolean in v1 |

### 3.3 Backward Compatibility: Boolean to String Migration

v1 used a boolean for `git.protectDefaultBranch`. v2 uses a string enum. The config loading code must handle both:

```bash
# In config.sh or git-utils.sh
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

This function MUST be called wherever `git.protectDefaultBranch` is read, to handle the boolean-to-string migration.

### 3.4 Enforcement in `pre-commit.sh`

v1 only warns when committing to the default branch. v2 adds `"block"` mode:

```bash
protect_mode=$(get_config "$CONFIG" '.git.protectDefaultBranch' 'warn')
protect_mode=$(normalize_protect_default_branch "$protect_mode")

if is_on_default_branch "$CONFIG" 2>/dev/null; then
  default_br=$(get_default_branch "$CONFIG")

  case "$protect_mode" in
    warn)
      # v1 behavior — allow with warning
      SYSTEM_MSG="[git-pilot] Warning: You are committing directly to '${default_br}'. Consider creating a feature branch first."
      ;;
    block)
      # v2 — prevent the commit
      output_block "[git-pilot] Commits to '${default_br}' are blocked by policy (git.protectDefaultBranch: block). Create a feature branch first using /branch."
      ;;
    off)
      # No protection
      ;;
  esac
fi
```

### 3.5 Mode Behavior and Backward Compatibility

| Mode | Behavior |
|------|----------|
| `"warn"` | Allow with warning (v1 behavior) |
| `"block"` | Prevent commit via `output_block` |
| `"off"` | No protection |

Backward compatibility: `true` -> `"warn"`, `false` -> `"off"`, unknown -> `"warn"`.

### 3.6 Test Scenarios

- `"warn"` mode -> warning emitted, commit allowed.
- `"block"` mode -> commit blocked with `output_block`.
- `"off"` mode -> no message.
- Boolean `true` -> treated as `"warn"`.
- Boolean `false` -> treated as `"off"`.

---

## 4. Hook Output Helper Functions

Defined in `scripts/pre-commit.sh` (v1), these functions standardize how hooks communicate decisions back to Claude Code. All emit JSON to stdout and call `exit`.

### 4.1 Allow Helpers

```bash
output_allow() {
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
JSON
  exit 0
}

output_allow_with_message() {
  local msg="$1"
  jq -n --arg msg "$msg" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow"},systemMessage:$msg}'
  exit 0
}

output_allow_with_updated_input() {
  local new_command="$1"
  jq -n --arg cmd "$new_command" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:{command:$cmd}}}'
  exit 0
}

output_allow_with_message_and_updated_input() {
  local msg="$1"; local new_command="$2"
  jq -n --arg msg "$msg" --arg cmd "$new_command" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:{command:$cmd}},systemMessage:$msg}'
  exit 0
}
```

### 4.2 `output_block()`

Rejects the tool invocation. The command is not executed. Writes the error to stderr and exits with code 2.

```bash
output_block() {
  local error_msg="$1"
  echo "$error_msg" >&2
  exit 2
}
```

**Usage across modules**: `output_block` -- protected branch `"block"` mode, commit validation failures. `output_allow_with_message` -- stash auto-save, branch warnings, freshness alerts. `output_allow_with_updated_input` -- signature stripping to rewrite commit commands.

---

## 5. Error Handling Invariants (applies to all sections)

### 5.1 Never Leave Broken State

- Stash operations that fail MUST NOT lose data (use `stash apply` before `stash drop` in manual flows; `stash pop` preserves stash on conflict).
- An in-progress rebase MUST be aborted: `git rebase --abort`.
- An in-progress merge MUST be aborted: `git merge --abort`.

### 5.2 User-Facing Error Message Pattern

All error messages follow: `[git-pilot] <context>: <specific error>. <suggestion>.`

Examples:
- `"[git-pilot] Rebase failed: could not apply commit abc1234. Conflicts in 2 file(s). Resolve conflicts or run 'git rebase --abort' to cancel."`
- `"[git-pilot] Stash restore failed: conflicts in src/main.rs. Run 'git stash pop' manually to resolve."`

### 5.3 Config Parse Failure

Fall back to defaults. Emit: `"[git-pilot] Warning: Could not parse config file. Using defaults."`

### 5.4 State File Failure

Emit warning. Disable state-dependent features for this session (including stash tracking). Do not crash.
