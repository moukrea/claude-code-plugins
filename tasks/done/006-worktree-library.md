# Task 006: Worktree Library

## Status
done

## Dependencies
- 001-config-schema (needs `get_config()` for `worktree.enabled`, `worktree.basePath`, `worktree.cleanupOnMerge` config keys)

## Spec References
- spec/04-agent-and-worktree.md (sections 2.1 through 2.8)

## Scope
Implement `scripts/worktree.sh` containing four public functions (`create_worktree()`, `remove_worktree()`, `list_worktrees()`, `merge_worktree_branch()`) and two internal registry functions (`register_worktree()`, `unregister_worktree()`). The registry is a JSON file at `$(git rev-parse --git-dir)/git-pilot-worktrees.json` with atomic write semantics. Also adds the `worktree.*` default config keys. This task does NOT integrate worktree calls into session hooks or agent orchestration; it provides the standalone library.

## Acceptance Criteria
- [x] `plugins/git-pilot/scripts/worktree.sh` exists, starts with `#!/usr/bin/env bash` and `set -euo pipefail`, sources `config.sh` from the same directory
- [x] `create_worktree()` creates a git worktree at the resolved path (replacing `{{project}}` placeholder and sanitizing `/` to `-` in branch names), registers it, and echoes the worktree path on success
- [x] `create_worktree()` returns exit code 1 and writes `error:<output>` to stderr on failure
- [x] `remove_worktree()` removes the worktree (with optional `--force` flag) and unregisters it from the registry
- [x] `list_worktrees()` returns the full registry JSON (`{"worktrees": [...]}`) or `{"worktrees":[]}` if no registry file exists
- [x] `merge_worktree_branch()` merges the worktree branch into the target branch, and if `worktree.cleanupOnMerge` is `true`, removes the worktree and deletes the branch
- [x] Config keys `worktree.enabled`, `worktree.basePath`, and `worktree.cleanupOnMerge` are read via `get_config()` (already defined in `defaults/config.json` by task 001)

## Implementation Notes

### File: `plugins/git-pilot/scripts/worktree.sh`

Source `config.sh` (for `get_config()`). Define `WORKTREE_REGISTRY` at module scope:
```bash
WORKTREE_REGISTRY="$(git rev-parse --git-dir 2>/dev/null)/git-pilot-worktrees.json"
```

Use `git rev-parse --git-dir` instead of hardcoded `.git` -- this is critical for correctness inside worktree contexts where `.git` is a file, not a directory.

**`create_worktree()` function** (spec section 2.2):
```bash
create_worktree() {
  local config="$1"
  local branch_name="$2"
  local base_branch="$3"
  local session_id="${4:-}"

  local project_name
  project_name=$(basename "$(git rev-parse --show-toplevel)")

  local base_path
  base_path=$(get_config "$config" '.worktree.basePath' "../{{project}}-worktrees")
  base_path="${base_path//\{\{project\}\}/$project_name}"

  local dir_name
  dir_name=$(echo "$branch_name" | tr '/' '-')
  local worktree_path="${base_path}/${dir_name}"

  mkdir -p "$(dirname "$worktree_path")"

  local output
  if output=$(git worktree add "$worktree_path" -b "$branch_name" "$base_branch" 2>&1); then
    register_worktree "$worktree_path" "$branch_name" "$base_branch" "$session_id"
    echo "$worktree_path"
    return 0
  else
    echo "error:${output}" >&2
    return 1
  fi
}
```

Parameters: `$1` = config JSON, `$2` = branch name, `$3` = base branch to create from, `$4` = session ID (optional).
Returns: echoes the absolute worktree path on stdout on success. On failure, writes `error:<git output>` to stderr.

Error message pattern for callers: `"[git-pilot] Worktree creation failed: branch 'feat/auth' already exists. Use a different name or delete the existing branch."`

The `{{project}}` placeholder in `basePath` is replaced with `$(basename "$(git rev-parse --show-toplevel)")`. Branch name `/` characters are replaced with `-` for directory names (e.g., `feat/auth` becomes `feat-auth`).

**`remove_worktree()` function** (spec section 2.3):
```bash
remove_worktree() {
  local worktree_path="$1"
  local force="${2:-false}"

  local flags=""
  if [[ "$force" == "true" ]]; then
    flags="--force"
  fi

  if git worktree remove "$worktree_path" $flags 2>/dev/null; then
    unregister_worktree "$worktree_path"
    return 0
  else
    return 1
  fi
}
```

Parameters: `$1` = worktree path, `$2` = "true" for force removal (optional, default "false").
Note: `$flags` is intentionally unquoted to allow word splitting when `--force` is set and to be empty (no argument) when not.

**`register_worktree()` function** (spec section 2.4):
```bash
register_worktree() {
  local path="$1"
  local branch="$2"
  local base_branch="$3"
  local session_id="${4:-}"

  local registry
  if [[ -f "$WORKTREE_REGISTRY" ]]; then
    registry=$(cat "$WORKTREE_REGISTRY")
  else
    registry='{"worktrees":[]}'
  fi

  local entry
  entry=$(jq -n \
    --arg p "$path" \
    --arg b "$branch" \
    --arg bb "$base_branch" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sid "$session_id" \
    '{path:$p, branch:$b, baseBranch:$bb, createdAt:$ts, createdBy:$sid, status:"active"}')

  registry=$(echo "$registry" | jq --argjson e "$entry" '.worktrees += [$e]')

  local tmp="${WORKTREE_REGISTRY}.tmp.$$"
  echo "$registry" > "$tmp" && mv "$tmp" "$WORKTREE_REGISTRY"
}
```

Registry file: `$(git rev-parse --git-dir)/git-pilot-worktrees.json`.
Entry schema: `{path, branch, baseBranch, createdAt, createdBy, status}`.
All writes use atomic temp-file + `mv` pattern (same as state.sh).

**`unregister_worktree()` function** (spec section 2.4):
```bash
unregister_worktree() {
  local path="$1"
  if [[ ! -f "$WORKTREE_REGISTRY" ]]; then
    return
  fi
  local registry
  registry=$(cat "$WORKTREE_REGISTRY")
  registry=$(echo "$registry" | jq --arg p "$path" \
    '.worktrees = [.worktrees[] | select(.path != $p)]')
  local tmp="${WORKTREE_REGISTRY}.tmp.$$"
  echo "$registry" > "$tmp" && mv "$tmp" "$WORKTREE_REGISTRY"
}
```

jq filter: `.worktrees = [.worktrees[] | select(.path != $p)]` -- removes the entry matching the path.

**`list_worktrees()` function** (spec section 2.4):
```bash
list_worktrees() {
  if [[ -f "$WORKTREE_REGISTRY" ]]; then
    cat "$WORKTREE_REGISTRY"
  else
    echo '{"worktrees":[]}'
  fi
}
```

Returns the full JSON registry or an empty-list structure.

**`merge_worktree_branch()` function** (spec section 2.5):
```bash
merge_worktree_branch() {
  local worktree_path="$1"
  local target_branch="$2"
  local config="$3"

  local wt_branch
  wt_branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null)

  if [[ -z "$wt_branch" ]]; then
    echo "error:cannot-determine-branch"
    return 1
  fi

  git checkout "$target_branch" 2>/dev/null || return 1

  local merge_output
  if merge_output=$(git merge "$wt_branch" --no-edit 2>&1); then
    echo "success"
    local cleanup
    cleanup=$(get_config "$config" '.worktree.cleanupOnMerge' 'true')
    if [[ "$cleanup" == "true" ]]; then
      remove_worktree "$worktree_path" "false"
      git branch -d "$wt_branch" 2>/dev/null || true
    fi
    return 0
  else
    echo "conflict"
    return 1
  fi
}
```

Parameters: `$1` = worktree path, `$2` = target branch to merge into, `$3` = config JSON.
Return values: `success` (exit 0) | `conflict` (exit 1) | `error:cannot-determine-branch` (exit 1).

On success with `worktree.cleanupOnMerge == true`: removes the worktree via `remove_worktree()` and deletes the branch with `git branch -d`.

### Invariants (spec section 2.7):
- Half-created worktrees MUST be cleaned up. Every function that starts a multi-step git operation must have cleanup logic in its error path.
- Required: `git` >= 2.30, `jq` >= 1.6.

### Config keys (defined in `defaults/config.json` by task 001):
Config keys are already defined in `defaults/config.json` by task 001. This task only needs to READ them via `get_config()`.
```json
{
  "worktree": {
    "enabled": true,
    "basePath": "../{{project}}-worktrees",
    "cleanupOnMerge": true
  }
}
```

## Files to Create or Modify
- plugins/git-pilot/scripts/worktree.sh (new)
