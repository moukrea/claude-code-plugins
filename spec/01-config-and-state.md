# Module 01: Configuration and State

**Depends on:** none. This is the foundational module. All other modules source `config.sh` and `state.sh`.

---

## 1. Three-Tier Config Merge

Configuration uses a three-tier merge: plugin defaults -> global -> local. Local overrides global, global overrides defaults. The merge is a shallow recursive merge via `jq -s '.[0] * .[1]'`.

### 1.1 Config File Locations

| Priority | Path | Scope |
|----------|------|-------|
| 1 (lowest) | `${PLUGIN_ROOT}/defaults/config.json` | Plugin defaults |
| 2 | `~/.claude/git-pilot.json` | User global |
| 3 (highest) | `${CWD}/.claude/git-pilot.json` | Project local |

### 1.2 Config Loading Functions

```bash
# config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

load_config() {
  local cwd="${1:-.}"
  local defaults="$PLUGIN_ROOT/defaults/config.json"
  local global="$HOME/.claude/git-pilot.json"
  local local_cfg="$cwd/.claude/git-pilot.json"

  local result
  result=$(cat "$defaults")

  if [[ -f "$global" ]]; then
    result=$(echo "$result" | jq -s '.[0] * .[1]' - "$global" 2>/dev/null || echo "$result")
  fi

  if [[ -f "$local_cfg" ]]; then
    result=$(echo "$result" | jq -s '.[0] * .[1]' - "$local_cfg" 2>/dev/null || echo "$result")
  fi

  echo "$result"
}

get_config() {
  local config="$1"
  local key="$2"
  local default="$3"
  echo "$config" | jq -r "if ($key) == null then \"$default\" else ($key) end"
}
```

No changes are needed to the merge logic itself in v2. The `load_config()` and `get_config()` functions remain as shown above.

**Failure behavior**: If `jq` cannot parse a config file, the `2>/dev/null || echo "$result"` guard preserves the previous tier's result and processing continues. The caller should emit: `"[git-pilot] Warning: Could not parse config file. Using defaults."`

---

## 2. Complete v2 Config Schema (`defaults/config.json`)

```jsonc
{
  "git": {
    "defaultBranch": "main",
    "autoInit": true,
    "protectDefaultBranch": "warn",
    "autoFetch": true,
    "fetchRetries": 2,
    "fetchRetryDelaySec": 3
  },
  "branch": {
    "pattern": "{{type}}/{{description}}",
    "types": ["feat", "fix", "refactor", "docs", "test", "chore", "style", "perf", "build", "ci"],
    "descriptionSeparator": "-",
    "descriptionCase": "kebab",
    "maxLength": 72,
    "autoCreate": true,
    "unrelatedWorkDetection": true,
    "autoStashOnSwitch": true
  },
  "commit": {
    "pattern": "{{type}}({{scope}}): {{description}}",
    "types": ["feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert"],
    "maxSubjectLength": 72,
    "scopeRequired": false,
    "body": {
      "required": false,
      "wrap": 72,
      "includeChangedFiles": false
    },
    "signature": {
      "stripCoAuthoredBy": true,
      "stripAiAttribution": true,
      "stripSignedOffBy": false
    },
    "breakingChange": {
      "appendExclamation": true,
      "requireBody": true,
      "bodyPrefix": "BREAKING CHANGE: "
    }
  },
  "autoCommit": {
    "enabled": true,
    "mode": "suggest",
    "threshold": 3,
    "includeWip": false,
    "wipPrefix": "wip: "
  },
  "remote": {
    "promptForRemote": true,
    "skipRemotePrompt": false,
    "defaultName": "origin",
    "autoPush": false,
    "pushOnFinish": "ask"
  },
  "rebase": {
    "autoRebaseBeforePush": true,
    "conflictStrategy": "prompt",
    "allowForcePush": "ask"
  },
  "mergeRequest": {
    "enabled": true,
    "createOnFinish": "ask",
    "platform": "auto",
    "titleFromBranch": true,
    "bodyTemplate": null,
    "draft": false,
    "labels": [],
    "assignToSelf": true
  },
  "worktree": {
    "enabled": true,
    "basePath": "../{{project}}-worktrees",
    "cleanupOnMerge": true
  },
  "agentTeams": {
    "suppressPromptsForAgents": true,
    "orchestratorOnly": ["push", "mr"]
  },
  "summary": {
    "includeFileChanges": true,
    "includeDiff": false,
    "includeCommitLog": true,
    "format": "markdown"
  }
}
```

### 2.1 New Config Keys Reference (v2)

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `git.autoFetch` | boolean | `true` | Run `git fetch` on session start |
| `git.fetchRetries` | integer | `2` | Number of retry attempts on fetch failure |
| `git.fetchRetryDelaySec` | integer | `3` | Seconds between fetch retries |
| `git.protectDefaultBranch` | string | `"warn"` | `"warn"` / `"block"` / `"off"` -- was boolean in v1 |
| `branch.unrelatedWorkDetection` | boolean | `true` | Enable unrelated work detection prompts |
| `branch.autoStashOnSwitch` | boolean | `true` | Auto-stash uncommitted changes on branch switch |
| `rebase.autoRebaseBeforePush` | boolean | `true` | Rebase onto base branch before push/MR |
| `rebase.conflictStrategy` | string | `"prompt"` | `"prompt"` / `"abort"` / `"merge-fallback"` |
| `rebase.allowForcePush` | string | `"ask"` | `"ask"` / `"never"` / `"always"` |
| `worktree.enabled` | boolean | `true` | Enable worktree management for Agent Teams |
| `worktree.basePath` | string | `"../{{project}}-worktrees"` | Worktree directory pattern |
| `worktree.cleanupOnMerge` | boolean | `true` | Remove worktree after successful merge |
| `agentTeams.suppressPromptsForAgents` | boolean | `true` | Suppress interactive prompts for spawned agents |
| `agentTeams.orchestratorOnly` | array | `["push", "mr"]` | Operations restricted to orchestrator agent |

---

## 3. Backward Compatibility: `protectDefaultBranch` Boolean-to-String Migration

v1 used a boolean for `git.protectDefaultBranch`. v2 uses a string enum (`"warn"`, `"block"`, `"off"`). The config loading code must handle both transparently.

### 3.1 `normalize_protect_default_branch()` Function

This function **must** be called wherever `git.protectDefaultBranch` is read:

```bash
# In config.sh
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

Mapping:

| v1 value | v2 equivalent |
|----------|---------------|
| `true` | `"warn"` |
| `false` | `"off"` |

Unknown values default to `"warn"`.

### 3.2 Backward Compatibility Guarantees

1. All v1 config files work unchanged with v2.
2. The default behavior of v2 with a v1 config is identical to v1, except:
   - `git fetch` runs on session start (new behavior, can be disabled with `git.autoFetch: false`).
   - Branch freshness information is shown (informational only, no action forced).
   - The `UserPromptSubmit` hook runs (lightweight, emits context for unrelated work detection).
3. No existing config keys are removed.
4. The `protectDefaultBranch` boolean-to-string migration is handled transparently.
5. Missing new keys use defaults from `defaults/config.json` via the three-tier merge.

---

## 4. State Management Library (`state.sh`)

All hook scripts source `state.sh` for session state operations. The library uses an atomic write pattern (temp file + `mv`) to prevent data corruption.

### 4.1 Function Signatures

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `get_state_file` | `session_id` | Path string on stdout | Returns `/tmp/git-pilot-${session_id}.json` |
| `read_state` | `state_file` | JSON string on stdout | Reads state file; returns `{}` if missing |
| `write_state` | `state_file`, `content` | (none) | Atomic write via temp file + `mv`; warns on failure, never crashes |
| `init_state` | `session_id`, `working_branch?`, `previous_branch?`, `base_branch?`, `branch_purpose?` | (none) | Creates initial session state (v2 adds params 4-5) |
| `update_state` | `state_file`, `[jq_args...]`, `jq_filter` | (none) | Reads state, applies jq filter, writes back atomically |
| `cleanup_state` | `state_file` | (none) | Removes the session state file |

### 4.2 Key Implementations

```bash
# state.sh — atomic write (used by init_state, update_state)
write_state() {
  local state_file="$1" content="$2"
  local tmp_file="${state_file}.tmp.$$"
  if ! echo "$content" > "$tmp_file"; then
    echo "[git-pilot] Warning: Cannot access session state. Auto-commit tracking disabled for this session." >&2
    rm -f "$tmp_file"; return 0
  fi
  if ! mv "$tmp_file" "$state_file"; then
    echo "[git-pilot] Warning: Cannot access session state. Auto-commit tracking disabled for this session." >&2
    rm -f "$tmp_file"; return 0
  fi
}

# v2 init_state — called from session-start.sh
init_state() {
  local session_id="$1" working_branch="${2:-}" previous_branch="${3:-}"
  local base_branch="${4:-}" branch_purpose="${5:-}"
  local state_file head_at_start=""
  state_file=$(get_state_file "$session_id")
  if command -v git >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
    head_at_start=$(git rev-parse HEAD 2>/dev/null || true)
  fi
  local content
  content=$(jq -n \
    --arg sid "$session_id" --arg start "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg wb "$working_branch" --arg pb "$previous_branch" \
    --arg head "$head_at_start" --arg bb "$base_branch" --arg bp "$branch_purpose" \
    '{ sessionId:$sid, startTime:$start, workingBranch:$wb, previousBranch:$pb,
       headAtStart:$head, baseBranch:$bb, branchPurpose:$bp, changeCount:0,
       lastCommitAt:null, modifiedFiles:[], remoteSkipped:false, lastFetchAt:null,
       isAgent:false, agentRole:null, activeWorktrees:[], stashRefs:[] }')
  write_state "$state_file" "$content"
}

# update_state — supports extra jq args (e.g., --arg key val)
update_state() {
  local state_file="$1"; shift
  local current; current=$(read_state "$state_file")
  local updated; updated=$(echo "$current" | jq "$@")
  write_state "$state_file" "$updated"
}
```

### 4.3 Atomic Write Pattern

`write_state()` writes to `${state_file}.tmp.$$` (PID-suffixed), then renames via `mv` (atomic on POSIX). On failure, it emits a warning to stderr and returns 0 (never crashes).

---

## 5. Session State Schema

### 5.1 Complete Session State Object

```jsonc
{
  "sessionId": "abc123",
  "startTime": "2026-02-24T20:00:00Z",
  "workingBranch": "feat/add-dark-mode",
  "previousBranch": "main",
  "headAtStart": "a1b2c3d4",
  "baseBranch": "main",
  "branchPurpose": "add dark mode",
  "changeCount": 0,
  "lastCommitAt": null,
  "modifiedFiles": [],
  "remoteSkipped": false,
  "lastFetchAt": "2026-02-24T20:00:05Z",
  "isAgent": false,
  "agentRole": null,
  "activeWorktrees": [],
  "stashRefs": []
}
```

### 5.2 New Fields (v2)

| Field | Type | Description |
|-------|------|-------------|
| `baseBranch` | string | The branch this feature branch was created from or targets for MR |
| `branchPurpose` | string | Human-readable purpose derived from branch name (e.g., `"add dark mode"` from `feat/add-dark-mode`) |
| `lastFetchAt` | string\|null | ISO timestamp of last `git fetch` in this session |
| `isAgent` | boolean | Whether this session is a spawned agent (not orchestrator) |
| `agentRole` | string\|null | `"orchestrator"`, `"implementer"`, `"validator"`, or null |
| `activeWorktrees` | array | List of `{path, branch, createdAt}` objects for worktrees created in this session |
| `stashRefs` | array | List of `{ref, branch, message, createdAt}` for stashes created by git-pilot |

### 5.3 State File Location

Path: `/tmp/git-pilot-${SESSION_ID}.json`

State files are ephemeral and cleaned up on session stop. They are not shared between sessions. For cross-session persistence, see the Worktree Registry below.

---

## 6. Worktree Registry Schema

For multi-session worktree tracking, a registry file is stored at `.git/git-pilot-worktrees.json`. This registry persists across sessions, unlike session state files which are cleaned up on session stop.

### 6.1 Complete Registry Object

```jsonc
{
  "worktrees": [
    {
      "path": "../myproject-worktrees/feat-add-auth",
      "branch": "feat/add-auth",
      "baseBranch": "main",
      "createdAt": "2026-02-24T20:00:00Z",
      "createdBy": "session-abc123",
      "status": "active"
    }
  ]
}
```

### 6.2 Registry Fields

| Field | Type | Description |
|-------|------|-------------|
| `worktrees` | array | List of worktree entries |
| `worktrees[].path` | string | Filesystem path to the worktree directory |
| `worktrees[].branch` | string | Branch checked out in the worktree |
| `worktrees[].baseBranch` | string | Branch this worktree's branch was created from |
| `worktrees[].createdAt` | string | ISO timestamp of worktree creation |
| `worktrees[].createdBy` | string | Session ID that created this worktree |
| `worktrees[].status` | string | `"active"` or other status values |

### 6.3 Registry Location

Path: `${GIT_DIR}/git-pilot-worktrees.json` (typically `.git/git-pilot-worktrees.json`).

The registry lives inside `.git/` so it is not committed to the repository but persists across sessions for the same clone.

---

## 7. Protected Branch Behavior by Mode

The `git.protectDefaultBranch` config key (after normalization) controls behavior when committing to the default branch:

| Mode | Behavior |
|------|----------|
| `"warn"` | Warning emitted via systemMessage, commit allowed |
| `"block"` | Commit blocked with exit code 2 |
| `"off"` | No message, no restriction |

---

## 8. Error Handling

Error handling for config and state operations (see TECHNICAL-SPEC SS6.1 for the full taxonomy):

| Error | Handling | Message |
|-------|----------|---------|
| Config parse failure | Fall back to previous tier via `2>/dev/null \|\| echo "$result"` | `"[git-pilot] Warning: Could not parse config file. Using defaults."` |
| State file failure | `write_state()` warns and returns 0; state-dependent features disabled | `"[git-pilot] Warning: Cannot access session state. Auto-commit tracking disabled for this session."` |
| Missing `git` | Warn at session start; git features disabled | `"[git-pilot] Warning: git is not installed. Git workflow features are disabled."` |
| Missing `jq` | Warn at session start; config loading degraded | `"[git-pilot] Warning: jq is not installed. Configuration loading may not work correctly."` |

The plugin never crashes on these errors. Dependencies are checked via `command -v` at session start.

---

## 9. Version Bump

`plugin.json` version changes from `"1.1.0"` to `"2.0.0"` because:
- `git.protectDefaultBranch` type changed from boolean to string (breaking for strict consumers).
- New behavioral rules in CLAUDE.md change default agent behavior.
- New hook (`UserPromptSubmit`) changes the lifecycle.