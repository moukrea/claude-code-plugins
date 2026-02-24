# Module 02: Git Utilities and Network

## Cross-references

- **Depends on `01-config-and-state.md`** for:
  - `get_config()` function signature used to read config values (e.g., `get_config "$config" '.git.fetchRetries' '2'`).
  - Config schema: `git.autoFetch`, `git.fetchRetries`, `git.fetchRetryDelaySec`, `remote.defaultName`.
  - Session state schema: `lastFetchAt` field, `write_state()` / `update_state()` for atomic state writes.
  - Three-tier config merge: plugin defaults -> global (`~/.claude/git-pilot.json`) -> local (`.claude/git-pilot.json`).

---

## Overview

This module covers `scripts/git-utils.sh`, which provides core git utility functions used by every hook script:

1. **Core Utility Functions** -- v1 functions (`is_git_repo`, `has_remote`, `get_current_branch`, etc.) used by all downstream modules.
2. **Branch Freshness Detection** (TECHNICAL-SPEC SS4.1) -- runs at session start to detect whether the current branch is behind, ahead, diverged, or has no remote tracking branch, and takes automatic action (fast-forward) or emits a systemMessage.
3. **Network Error Handling** (TECHNICAL-SPEC SS4.10) -- provides retry logic for `git fetch` and defines messages for network failures.
4. **Branch Purpose Derivation** (TECHNICAL-SPEC SS4.4) -- derives human-readable purpose from branch names for unrelated work detection.

---

## 1. Branch Freshness Detection

**Trigger**: SessionStart hook (`session-start.sh`)

**Preconditions**: Repository has at least one remote. `git.autoFetch` is `true`.

### 1.1 Behavior

1. Run `git fetch ${remote_name}` with retry logic (see Section 2 below).
2. Record `lastFetchAt` in session state.
3. Determine the current branch's tracking status using `get_branch_tracking_status()`.
4. Emit systemMessage based on status.
5. For `behind` status, attempt fast-forward auto-merge.

### 1.2 `get_branch_tracking_status()` Function

Location: `scripts/git-utils.sh`

```bash
get_branch_tracking_status() {
  local branch="$1"
  local remote_name="$2"
  local remote_branch="${remote_name}/${branch}"

  # Check if remote branch exists
  if ! git rev-parse --verify "$remote_branch" >/dev/null 2>&1; then
    echo "no-remote"
    return
  fi

  local local_ref remote_ref base_ref
  local_ref=$(git rev-parse "$branch" 2>/dev/null)
  remote_ref=$(git rev-parse "$remote_branch" 2>/dev/null)
  base_ref=$(git merge-base "$branch" "$remote_branch" 2>/dev/null || true)

  if [[ "$local_ref" == "$remote_ref" ]]; then
    echo "up-to-date"
  elif [[ "$local_ref" == "$base_ref" ]]; then
    local behind_count
    behind_count=$(git rev-list --count "${branch}..${remote_branch}" 2>/dev/null)
    echo "behind:${behind_count}"
  elif [[ "$remote_ref" == "$base_ref" ]]; then
    local ahead_count
    ahead_count=$(git rev-list --count "${remote_branch}..${branch}" 2>/dev/null)
    echo "ahead:${ahead_count}"
  else
    local ahead_count behind_count
    ahead_count=$(git rev-list --count "${remote_branch}..${branch}" 2>/dev/null)
    behind_count=$(git rev-list --count "${branch}..${remote_branch}" 2>/dev/null)
    echo "diverged:${ahead_count}:${behind_count}"
  fi
}
```

**Return values**:

| Return value | Meaning |
|---|---|
| `no-remote` | Remote tracking branch does not exist (new branch, not yet pushed) |
| `up-to-date` | Local and remote refs are identical |
| `behind:N` | Local branch is N commits behind the remote tracking branch |
| `ahead:N` | Local branch is N commits ahead of the remote tracking branch |
| `diverged:A:B` | Local is A commits ahead and B commits behind the remote (history has diverged) |

### 1.3 systemMessages by Status

| Status | Action | systemMessage |
|---|---|---|
| `up-to-date` | None | No message |
| `behind:N` | Auto fast-forward | `"[git-pilot] Branch '${branch}' was ${N} commit(s) behind '${remote}/${branch}'. Fast-forwarded to latest."` |
| `behind:N` (ff fails) | Warn | `"[git-pilot] Branch '${branch}' is ${N} commit(s) behind '${remote}/${branch}' but fast-forward failed. Prompt the user: pull with merge, reset to remote, or continue as-is."` |
| `ahead:N` | Inform | `"[git-pilot] Branch '${branch}' is ${N} commit(s) ahead of '${remote}/${branch}'. Unpushed changes."` |
| `diverged:A:B` | Warn | `"[git-pilot] Branch '${branch}' has diverged from '${remote}/${branch}' (${A} local, ${B} remote). Prompt the user: rebase onto remote, merge remote, reset to remote, or continue."` |
| `no-remote` | Inform | No message (new branch, not yet pushed) |

### 1.4 Fast-Forward Auto-Merge Logic

When status is `behind:N` (local branch is behind remote with no local-only commits):

```bash
if git merge --ff-only "${remote_branch}" >/dev/null 2>&1; then
  # Success -- emit fast-forward message
else
  # Cannot fast-forward -- emit warning with options
fi
```

The fast-forward is attempted automatically. If it succeeds, the success systemMessage is emitted. If it fails (e.g., dirty working tree), the warning systemMessage with user options is emitted instead.

### 1.5 Edge Cases

- If `git.autoFetch` is `false`, skip fetch entirely. Still check local vs. tracking branch status if tracking info exists.
- If no remote exists, skip all freshness checks.
- If the branch has no tracking branch (new local branch), skip comparison.
- If fetch fails after all retries, emit a warning and continue without freshness data (see Section 2).

---

## 2. Network Error Handling

**Modified file**: `scripts/git-utils.sh`

### 2.1 `fetch_with_retry()` Function

```bash
fetch_with_retry() {
  local remote_name="$1"
  local config="$2"
  local specific_branch="${3:-}"

  local max_retries
  max_retries=$(get_config "$config" '.git.fetchRetries' '2')
  local retry_delay
  retry_delay=$(get_config "$config" '.git.fetchRetryDelaySec' '3')

  local fetch_args="$remote_name"
  if [[ -n "$specific_branch" ]]; then
    fetch_args="$remote_name $specific_branch"
  fi

  local attempt=0
  local last_error=""

  while (( attempt <= max_retries )); do
    if git fetch $fetch_args 2>/dev/null; then
      return 0
    fi

    last_error=$(git fetch $fetch_args 2>&1 || true)
    attempt=$((attempt + 1))

    if (( attempt <= max_retries )); then
      sleep "$retry_delay"
    fi
  done

  # All retries exhausted
  echo "$last_error" >&2
  return 1
}
```

### 2.2 Config Keys

| Key | Type | Default | Description |
|---|---|---|---|
| `git.autoFetch` | boolean | `true` | Run `git fetch` on session start |
| `git.fetchRetries` | integer | `2` | Number of retry attempts on fetch failure |
| `git.fetchRetryDelaySec` | integer | `3` | Seconds between fetch retries |

### 2.3 Retry Behavior

- The initial fetch attempt (attempt 0) plus up to `git.fetchRetries` retries are performed.
- Retries are silent (no systemMessage emitted during retries).
- `sleep "$retry_delay"` is called between attempts.
- If a `specific_branch` is provided (third argument), only that branch is fetched. Otherwise all refs from the remote are fetched.
- On success at any attempt, the function returns 0 immediately.
- On total failure, `last_error` is written to stderr and the function returns 1.

### 2.4 Network Error Messages

| Event | systemMessage |
|---|---|
| Fetch failed, retrying | (no message -- retries are silent) |
| All retries exhausted | `"[git-pilot] Warning: Could not fetch from '${remote}' after ${retries} attempts. Network may be unavailable. Proceeding without remote sync."` |
| Push failed (network) | `"[git-pilot] Push to '${remote}/${branch}' failed. Check network connectivity and try again."` |

### 2.5 Integration with Branch Freshness

The `session-start.sh` script calls `fetch_with_retry()` before calling `get_branch_tracking_status()`. If `fetch_with_retry()` fails (returns 1), the session-start script emits the "all retries exhausted" warning and continues without freshness data. The `lastFetchAt` field in session state is only updated on a successful fetch.

---

## 3. Related Config Defaults

For reference, the relevant subset of the default config (`defaults/config.json`):

```jsonc
{
  "git": {
    "defaultBranch": "main",
    "autoFetch": true,
    "fetchRetries": 2,
    "fetchRetryDelaySec": 3
  },
  "remote": {
    "defaultName": "origin"
  }
}
```

---

## 4. Session State Fields Used

| Field | Type | Description |
|---|---|---|
| `lastFetchAt` | string\|null | ISO timestamp of last successful `git fetch` in this session. Updated after `fetch_with_retry()` succeeds. |
| `workingBranch` | string | Current branch name, used as the `branch` argument to `get_branch_tracking_status()`. |
| `branchPurpose` | string | Human-readable purpose derived via `derive_branch_purpose()`. |

---

## 5. Core Utility Functions

These v1 functions in `scripts/git-utils.sh` are used by all downstream modules and hook scripts. They are sourced (not invoked as subprocesses).

```bash
# git-utils.sh

is_git_repo() {
  git rev-parse --git-dir >/dev/null 2>&1
}

get_current_branch() {
  git branch --show-current 2>/dev/null
}

has_uncommitted_changes() {
  [[ -n "$(git status --porcelain 2>/dev/null)" ]]
}

get_default_branch() {
  local config="$1"
  echo "$config" | jq -r '.git.defaultBranch // "main"'
}

is_on_default_branch() {
  local config="$1"
  local current default_branch
  current=$(get_current_branch)
  default_branch=$(get_default_branch "$config")
  [[ "$current" == "$default_branch" ]]
}

has_remote() {
  [[ -n "$(git remote 2>/dev/null)" ]]
}

sanitize_branch_name() {
  local name="$1"
  echo "$name" | sed 's/[^a-zA-Z0-9._/-]//g'
}
```

### 5.1 Function Reference

| Function | Parameters | Returns | Used by |
|----------|-----------|---------|---------|
| `is_git_repo` | (none) | exit code 0/1 | `session-start.sh`, all hooks |
| `get_current_branch` | (none) | branch name on stdout (empty if detached HEAD) | `session-start.sh`, `pre-commit.sh`, `post-bash.sh` |
| `has_uncommitted_changes` | (none) | exit code 0 if dirty, 1 if clean | `session-start.sh`, `session-stop.sh`, `auto_stash()` |
| `get_default_branch` | `config` (JSON string) | branch name on stdout | `session-start.sh`, `pre-commit.sh`, `is_on_default_branch()` |
| `is_on_default_branch` | `config` (JSON string) | exit code 0/1 | `pre-commit.sh`, `session-start.sh` |
| `has_remote` | (none) | exit code 0/1 | `session-start.sh`, `post-bash.sh`, `session-stop.sh` |
| `sanitize_branch_name` | `name` (string) | sanitized name on stdout | branch creation flows |

---

## 6. Branch Purpose Derivation

Location: `scripts/git-utils.sh` (TECHNICAL-SPEC SS4.4)

Called by `session-start.sh` during state initialization to derive a human-readable purpose from the branch name. The result is stored in `branchPurpose` in session state and included in the SessionStart systemMessage so Claude has context for unrelated work detection.

### 6.1 `derive_branch_purpose()` Function

```bash
# In git-utils.sh
derive_branch_purpose() {
  local branch_name="$1"

  # Strip type prefix (e.g., "feat/", "fix/")
  local description
  description=$(echo "$branch_name" | sed 's|^[^/]*/||')

  # Convert kebab-case/snake_case to words
  description=$(echo "$description" | tr '-' ' ' | tr '_' ' ')

  echo "$description"
}
```

**Parameters**: `branch_name` (string, required) -- the full branch name (e.g., `feat/add-dark-mode`).

**Returns**: space-separated description on stdout (e.g., `add dark mode`).

### 6.2 Usage in `session-start.sh`

```bash
if [[ -n "$current_branch" ]] && [[ "$current_branch" != "$default_branch" ]]; then
  branch_purpose=$(derive_branch_purpose "$current_branch")
  configured_base=$(git config "branch.${current_branch}.merge" 2>/dev/null | sed 's|refs/heads/||' || true)
  if [[ -n "$configured_base" ]]; then
    base_branch="$configured_base"
  fi
fi
init_state "$SESSION_ID" "$current_branch" "$previous_branch" "$base_branch" "$branch_purpose"
```

### 6.3 Examples

| Branch name | `derive_branch_purpose` output |
|-------------|-------------------------------|
| `feat/add-dark-mode` | `add dark mode` |
| `fix/login-timeout` | `login timeout` |
| `refactor/extract_utils` | `extract utils` |
| `main` | `main` (no prefix to strip) |
