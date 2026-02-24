# Module 03: Rebase and Conflict Resolution

## Cross-references

- **Depends on `01-config-and-state.md`** for:
  - `get_config()` function signature used to read config values.
  - Config schema: `rebase.autoRebaseBeforePush`, `rebase.conflictStrategy`, `rebase.allowForcePush`, `git.defaultBranch`.
  - Session state schema: `baseBranch` field, `read_state()` / `update_state()`.
  - Three-tier config merge: plugin defaults -> global (`~/.claude/git-pilot.json`) -> local (`.claude/git-pilot.json`).
- **Depends on `02-git-utils-and-network.md`** for:
  - `fetch_with_retry()` function, called by `get_base_branch_drift()` to fetch the latest base branch state before computing drift.
  - Network error handling and retry behavior.

---

## Overview

This module covers two features:

1. **Base Branch Drift Detection** (TECHNICAL-SPEC SS4.2) -- determines whether the base branch (e.g., `main`) has new commits since the feature branch diverged, and initiates a rebase if needed.
2. **Intelligent Rebase and Conflict Resolution** (TECHNICAL-SPEC SS4.3) -- executes rebases, detects and reports conflicts with structured detail, applies configurable conflict strategies, and handles force push requirements.

**New library**: `scripts/rebase.sh`

---

## 1. Base Branch Drift Detection

**Trigger**: Before push or MR creation. Called from `/finish` skill, `session-stop.sh`, and `post-bash.sh` (on push commands).

**Preconditions**: On a feature branch (not default branch). Remote exists. `rebase.autoRebaseBeforePush` is `true`.

### 1.1 `get_base_branch_drift()` Function

Location: `scripts/git-utils.sh`

```bash
get_base_branch_drift() {
  local current_branch="$1"
  local base_branch="$2"
  local remote_name="$3"
  local remote_base="${remote_name}/${base_branch}"

  # Fetch latest base branch state
  git fetch "$remote_name" "$base_branch" 2>/dev/null || return 1

  # Find the merge base between current branch and remote base
  local merge_base
  merge_base=$(git merge-base "$current_branch" "$remote_base" 2>/dev/null || true)

  if [[ -z "$merge_base" ]]; then
    echo "no-common-ancestor"
    return
  fi

  # Count commits on base branch since the branch point
  local drift_count
  drift_count=$(git rev-list --count "${merge_base}..${remote_base}" 2>/dev/null)

  if [[ "$drift_count" -eq 0 ]]; then
    echo "no-drift"
  else
    echo "drifted:${drift_count}"
  fi
}
```

**Return values**:

| Return value | Meaning |
|---|---|
| `no-drift` | Base branch has no new commits since this branch diverged |
| `drifted:N` | Base branch has N new commits since the branch point |
| `no-common-ancestor` | Cannot determine a merge base between the branches |

### 1.2 Decision Flow

1. If `no-drift`: proceed with push/MR.
2. If `drifted:N`:
   a. Emit: `"[git-pilot] Base branch '${base}' has ${N} new commit(s) since this branch diverged. Rebasing '${current}' onto '${remote}/${base}'..."`
   b. Attempt rebase (see Section 2).
   c. If rebase succeeds: emit `"[git-pilot] Rebase succeeded cleanly. Ready to push."` and continue.
   d. If rebase has conflicts: handle per `rebase.conflictStrategy` (see Section 2.3).
3. If `no-common-ancestor`: emit warning: `"[git-pilot] Cannot determine common ancestor between '${current}' and '${base}'. Skipping rebase. Push may require manual review."` Proceed with push.

### 1.3 Base Branch Determination

The base branch is determined in order:

1. From session state `baseBranch` field (set when branch was created via `/branch` skill).
2. From git tracking: `git config branch.${current}.merge` -> strip `refs/heads/`.
3. Fall back to `git.defaultBranch` from config (default: `"main"`).

---

## 2. Intelligent Rebase and Conflict Resolution

### 2.1 `attempt_rebase()` Function

Location: `scripts/rebase.sh`

```bash
attempt_rebase() {
  local target_branch="$1"  # Branch to rebase onto (e.g., origin/main)

  # Ensure clean working tree
  if has_uncommitted_changes; then
    echo "error:dirty-worktree"
    return 1
  fi

  # Attempt rebase
  local rebase_output
  if rebase_output=$(git rebase "$target_branch" 2>&1); then
    echo "success"
    return 0
  else
    # Check if it's a conflict
    if git diff --name-only --diff-filter=U 2>/dev/null | head -1 | grep -q .; then
      echo "conflict"
      return 1
    else
      echo "error:${rebase_output}"
      return 1
    fi
  fi
}
```

**Return values**:

| Return value | Exit code | Meaning |
|---|---|---|
| `success` | 0 | Rebase completed cleanly |
| `conflict` | 1 | Rebase stopped due to merge conflicts |
| `error:dirty-worktree` | 1 | Working tree has uncommitted changes, cannot rebase |
| `error:${rebase_output}` | 1 | Rebase failed for another reason (output included) |

### 2.2 `get_conflict_details()` Function

Location: `scripts/rebase.sh`

Returns a JSON array describing each conflicting file.

```bash
get_conflict_details() {
  local conflict_files
  conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null)

  if [[ -z "$conflict_files" ]]; then
    echo "[]"
    return
  fi

  local result="["
  local first=true

  while IFS= read -r file; do
    # Determine conflict type by examining the conflict markers
    local ours_only=false
    local theirs_only=false
    local both_modified=false

    # Check if the file exists in both sides
    local ours_exists theirs_exists
    ours_exists=$(git ls-files --stage "$file" 2>/dev/null | grep "^[0-9]* [a-f0-9]* 2" | wc -l | tr -d ' ')
    theirs_exists=$(git ls-files --stage "$file" 2>/dev/null | grep "^[0-9]* [a-f0-9]* 3" | wc -l | tr -d ' ')

    local conflict_type="both-modified"
    if [[ "$ours_exists" == "0" ]]; then
      conflict_type="deleted-by-us"
    elif [[ "$theirs_exists" == "0" ]]; then
      conflict_type="deleted-by-them"
    fi

    # Get conflict marker count as complexity indicator
    local marker_count=0
    if [[ -f "$file" ]]; then
      marker_count=$(grep -c '^<<<<<<< ' "$file" 2>/dev/null || echo "0")
    fi

    if [[ "$first" == "true" ]]; then
      first=false
    else
      result+=","
    fi
    result+=$(jq -n \
      --arg f "$file" \
      --arg t "$conflict_type" \
      --argjson m "$marker_count" \
      '{file: $f, type: $t, conflictRegions: $m}')
  done <<< "$conflict_files"

  result+="]"
  echo "$result"
}
```

**JSON output format**:

```json
[
  {
    "file": "src/auth.ts",
    "type": "both-modified",
    "conflictRegions": 2
  },
  {
    "file": "src/utils.ts",
    "type": "deleted-by-us",
    "conflictRegions": 0
  }
]
```

**Field definitions**:

| Field | Type | Description |
|---|---|---|
| `file` | string | Relative file path of the conflicting file |
| `type` | string | One of: `both-modified`, `deleted-by-us`, `deleted-by-them` |
| `conflictRegions` | integer | Count of `<<<<<<< ` markers in the file (0 for delete conflicts) |

**Conflict type detection logic**:

- Stage 2 in `git ls-files --stage` = "ours" (current branch). Stage 3 = "theirs" (incoming branch).
- If stage 2 entry count is 0: `deleted-by-us`.
- If stage 3 entry count is 0: `deleted-by-them`.
- Otherwise: `both-modified`.

### 2.3 Conflict Resolution Messages

When conflicts are detected, the hook emits a systemMessage with structured conflict information:

```
[git-pilot] Rebase conflict in ${count} file(s):

${for each conflict}
- `${file}` (${type}, ${regions} conflict region(s))
  Recommendation: ${recommendation}
${end for}

Prompt the user with these options:
1. Resolve conflicts manually (edit the conflicting files, then run `git add <file>` and `git rebase --continue`)
2. Accept all changes from the base branch (`git checkout --theirs <file>` for each file)
3. Keep all local changes (`git checkout --ours <file>` for each file)
4. Abort the rebase (`git rebase --abort`) and push without rebasing
5. Abort the rebase and use merge instead (`git merge ${base_branch}`)
```

### 2.4 Conflict Recommendation Heuristics

| Conflict type | Condition | Recommendation |
|---|---|---|
| `deleted-by-us` | -- | `"File was deleted locally but modified on base. If the deletion was intentional, accept ours (delete). Otherwise, accept theirs."` |
| `deleted-by-them` | -- | `"File was deleted on base but modified locally. If your changes are still needed, accept ours. Otherwise, accept theirs (delete)."` |
| `both-modified` | 1 region | `"Single conflict region -- likely a small overlap. Manual review recommended."` |
| `both-modified` | >3 regions | `"Multiple conflict regions -- significant concurrent changes. Manual review required."` |

### 2.5 `rebase.conflictStrategy` Handling

Config key: `rebase.conflictStrategy` (default: `"prompt"`)

| Strategy | Behavior |
|---|---|
| `"prompt"` | Emit conflict details and prompt user for resolution choice (default) |
| `"abort"` | Immediately abort rebase: `git rebase --abort`. Emit: `"[git-pilot] Rebase aborted due to conflicts. Push without rebase."` |
| `"merge-fallback"` | Abort rebase, attempt merge instead: `git rebase --abort && git merge ${target}`. If merge also conflicts, fall back to `"prompt"` behavior |

---

## 3. Force Push Handling

### 3.1 `needs_force_push()` Function

Location: `scripts/rebase.sh`

After a successful rebase that rewrites history (branch was previously pushed), a force push is needed.

```bash
needs_force_push() {
  local branch="$1"
  local remote_name="$2"

  # Check if remote tracking branch exists
  if ! git rev-parse --verify "${remote_name}/${branch}" >/dev/null 2>&1; then
    return 1  # No remote branch, normal push works
  fi

  # Check if local and remote have diverged after rebase
  local local_ref remote_ref
  local_ref=$(git rev-parse "$branch" 2>/dev/null)
  remote_ref=$(git rev-parse "${remote_name}/${branch}" 2>/dev/null)

  if [[ "$local_ref" != "$remote_ref" ]]; then
    # Check if remote is NOT an ancestor of local (diverged, not just ahead)
    if ! git merge-base --is-ancestor "$remote_ref" "$local_ref" 2>/dev/null; then
      return 0  # Needs force push
    fi
  fi

  return 1
}
```

**Logic**: Returns 0 (true / needs force push) when:
1. The remote tracking branch exists, AND
2. Local and remote refs differ, AND
3. The remote ref is NOT an ancestor of the local ref (i.e., history has diverged, not just new commits ahead).

Returns 1 (false / normal push is fine) otherwise.

### 3.2 `rebase.allowForcePush` Handling

Config key: `rebase.allowForcePush` (default: `"ask"`)

| Setting | Behavior |
|---|---|
| `"ask"` | Emit: `"[git-pilot] Rebase rewrote history. Force push required. Prompt the user: force push (git push --force-with-lease) or abort."` |
| `"never"` | Emit: `"[git-pilot] Rebase rewrote history but force push is disabled. The rebase changes are local only. Push manually if needed."` |
| `"always"` | Use `git push --force-with-lease` automatically. Emit: `"[git-pilot] Force-pushed '${branch}' to '${remote}/${branch}' after rebase."` |

Always use `--force-with-lease` (never bare `--force`) for safety.

---

## 4. Push Rejection Detection and Messages

Location: `post-bash.sh`

When `post-bash.sh` detects a failed `git push` (exit code non-zero, stderr contains "rejected" or "failed to push"):

```
[git-pilot] Push rejected -- remote '${remote}/${branch}' has new commits.
Prompt the user:
1. Pull and rebase, then retry push (`git pull --rebase && git push`)
2. Force push with lease (`git push --force-with-lease`) -- overwrites remote changes
3. Pull and merge (`git pull`) -- creates a merge commit
4. Cancel
```

---

## 5. Related Config Defaults

For reference, the relevant subset of the default config (`defaults/config.json`):

```jsonc
{
  "git": {
    "defaultBranch": "main"
  },
  "rebase": {
    "autoRebaseBeforePush": true,
    "conflictStrategy": "prompt",
    "allowForcePush": "ask"
  }
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `rebase.autoRebaseBeforePush` | boolean | `true` | Rebase onto base branch before push/MR |
| `rebase.conflictStrategy` | string | `"prompt"` | `"prompt"` / `"abort"` / `"merge-fallback"` |
| `rebase.allowForcePush` | string | `"ask"` | `"ask"` / `"never"` / `"always"` |

---

## 6. Session State Fields Used

| Field | Type | Description |
|---|---|---|
| `baseBranch` | string | The branch this feature branch targets for MR / was created from. Used as the `base_branch` argument to `get_base_branch_drift()`. |
| `workingBranch` | string | Current branch name, used as the `current_branch` argument to `get_base_branch_drift()`. |
