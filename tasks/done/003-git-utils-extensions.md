# Task 003: Git Utils Extensions

## Status
done

## Dependencies
- 001-config-schema (needs v2 config schema for `get_config()` calls reading `git.fetchRetries`, `git.fetchRetryDelaySec`, and `remote.defaultName`)

## Spec References
- spec/02-git-utils-and-network.md

## Scope
Add four new functions to `git-utils.sh`: `get_branch_tracking_status()` for branch freshness detection, `fetch_with_retry()` for network-resilient fetching with configurable retries, `derive_branch_purpose()` for extracting human-readable purpose from branch names, and `is_detached_head()` as a utility for detached HEAD detection. All existing v1 functions in the file remain unchanged.

## Acceptance Criteria
- [x] `get_branch_tracking_status()` accepts `branch` and `remote_name`, returns one of: `no-remote`, `up-to-date`, `behind:N`, `ahead:N`, `diverged:A:B` on stdout.
- [x] `fetch_with_retry()` accepts `remote_name`, `config` (JSON string), and optional `specific_branch`. It reads `git.fetchRetries` (default `2`) and `git.fetchRetryDelaySec` (default `3`) from config via `get_config()`. Returns 0 on success, 1 after all retries exhausted (with last error on stderr).
- [x] `derive_branch_purpose()` accepts a branch name string and returns the description portion with hyphens and underscores converted to spaces (e.g., `feat/add-dark-mode` -> `add dark mode`).
- [x] `is_detached_head()` returns exit code 0 if HEAD is detached, 1 otherwise.
- [x] All existing v1 functions (`is_git_repo`, `get_current_branch`, `has_uncommitted_changes`, `get_default_branch`, `is_on_default_branch`, `has_remote`, `sanitize_branch_name`) are unchanged.
- [x] Retries in `fetch_with_retry()` are silent (no messages emitted during retry loop); only `last_error` is written to stderr on total failure.

## Implementation Notes

### `get_branch_tracking_status()` -- branch freshness

Append to `git-utils.sh`. Full implementation from spec Section 1.2:

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

Return value format reference:

| Return value | Meaning |
|---|---|
| `no-remote` | Remote tracking branch does not exist |
| `up-to-date` | Local and remote refs are identical |
| `behind:N` | Local is N commits behind remote |
| `ahead:N` | Local is N commits ahead of remote |
| `diverged:A:B` | Local is A ahead, B behind remote |

### `fetch_with_retry()` -- network-resilient fetch

Append to `git-utils.sh`. Full implementation from spec Section 2.1:

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

Important: `fetch_args` is intentionally unquoted in `git fetch $fetch_args` so that word splitting separates remote name and branch. The `get_config()` function is defined in `config.sh` which is sourced before `git-utils.sh` by all hook scripts.

Retry behavior:
- Attempt 0 is the initial try; up to `max_retries` additional attempts follow.
- `sleep "$retry_delay"` is called between attempts (not after the last failure).
- Retries are silent -- no systemMessage emitted during the loop.
- On total failure, `last_error` (stderr from the last `git fetch`) is written to stderr and function returns 1.

### `derive_branch_purpose()` -- human-readable branch purpose

Append to `git-utils.sh`. From spec Section 6.1:

```bash
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

Examples from spec:

| Branch name | Output |
|---|---|
| `feat/add-dark-mode` | `add dark mode` |
| `fix/login-timeout` | `login timeout` |
| `refactor/extract_utils` | `extract utils` |
| `main` | `main` (no `/` to split on, `sed` leaves it unchanged) |

### `is_detached_head()` -- detached HEAD check

Append to `git-utils.sh`:

```bash
is_detached_head() {
  [[ -z "$(git branch --show-current 2>/dev/null)" ]] && git rev-parse HEAD >/dev/null 2>&1
}
```

Returns exit code 0 if HEAD is detached (no current branch name but HEAD is valid), 1 otherwise. This is used by `session-start.sh` to detect detached HEAD state and skip branch-related workflows.

### Ordering of new functions

Append all four functions after the existing `sanitize_branch_name()` at the end of the file, separated by blank lines, in this order:
1. `is_detached_head()`
2. `get_branch_tracking_status()`
3. `fetch_with_retry()`
4. `derive_branch_purpose()`

## Files to Create or Modify
- plugins/git-pilot/scripts/git-utils.sh (modify)
