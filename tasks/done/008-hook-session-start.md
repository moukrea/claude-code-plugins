# Task 008: Hook session-start.sh Modifications

## Status
done

## Dependencies
- 001-config-schema (uses `get_config()` for `.git.autoFetch`, `.git.fetchRetries`, `.remote.defaultName`, `.branch.unrelatedWorkDetection`)
- 002-state-schema (uses `init_state()` with extended 5-arg signature: `session_id`, `current_branch`, `previous_branch`, `base_branch`, `branch_purpose`)
- 003-git-utils-extensions (uses `fetch_with_retry()`, `get_branch_tracking_status()`, `derive_branch_purpose()`, `has_remote()`)

## Spec References
- spec/06-hooks-and-lifecycle.md (sections 3a, 3b, 3c, 3d)
- spec/05-stash-and-robustness.md (section 2 -- detached HEAD recovery)

## Scope
Modify the existing `session-start.sh` script to add four new capabilities after the git init check: (a) remote fetch with retry, (b) branch freshness check with fast-forward or divergence messaging, (c) detached HEAD detection and recovery prompting, and (d) extended session state initialization with `baseBranch` and `branchPurpose` fields.

## Acceptance Criteria
- [x] After git init check (Step 6) and before branch detection (Step 7), fetch remote when `git.autoFetch` is `true` using `fetch_with_retry()`; emit warning on failure: `"[git-pilot] Warning: Could not fetch from '${remote_name}' after ${retries} attempts. Network may be unavailable. Proceeding without remote sync."`
- [x] After getting `current_branch`, check tracking status via `get_branch_tracking_status()` and emit appropriate messages for `behind:*` (attempt fast-forward), `diverged:*:*`, and `ahead:*` states
- [x] When `get_current_branch` returns empty, detect detached HEAD: look up previous branch via `git reflog show --format='%gs' | grep -m1 'checkout: moving from'`; emit 3-option message if previous branch found, 2-option if not
- [x] Extended `init_state` call passes 5 arguments: `session_id`, `current_branch`, `previous_branch`, `base_branch`, `branch_purpose`; `base_branch` defaults to `default_branch` but checks `git config "branch.${current_branch}.merge"` for configured base
- [x] `derive_branch_purpose()` is called for non-default branches to populate `branchPurpose`
- [x] All new blocks are guarded by `is_git_repo` (and `has_remote` where network is needed)

## Implementation Notes

### 3a. Fetch remote -- insert after Step 6 (git init check), before Step 7 (branch detection)

```bash
if is_git_repo && has_remote; then
  auto_fetch=$(get_config "$CONFIG" '.git.autoFetch' 'true')
  remote_name=$(get_config "$CONFIG" '.remote.defaultName' 'origin')
  if [[ "$auto_fetch" == "true" ]]; then
    retries=$(get_config "$CONFIG" '.git.fetchRetries' '2')
    if ! fetch_with_retry "$remote_name" "$CONFIG"; then
      messages+=("[git-pilot] Warning: Could not fetch from '${remote_name}' after ${retries} attempts. Network may be unavailable. Proceeding without remote sync.")
    fi
  fi
fi
```

Config keys: `.git.autoFetch` (default `true`), `.git.fetchRetries` (default `2`), `.remote.defaultName` (default `'origin'`).

### 3b. Branch freshness -- insert after `current_branch` is assigned

```bash
if is_git_repo && has_remote && [[ -n "$current_branch" ]]; then
  remote_name=$(get_config "$CONFIG" '.remote.defaultName' 'origin')
  tracking_status=$(get_branch_tracking_status "$current_branch" "$remote_name")
  case "$tracking_status" in
    behind:*)
      behind_count="${tracking_status#behind:}"
      if git merge --ff-only "${remote_name}/${current_branch}" >/dev/null 2>&1; then
        messages+=("[git-pilot] Branch '${current_branch}' was ${behind_count} commit(s) behind '${remote_name}/${current_branch}'. Fast-forwarded to latest.")
      else
        messages+=("[git-pilot] Branch '${current_branch}' is ${behind_count} commit(s) behind '${remote_name}/${current_branch}' but fast-forward failed. Prompt the user: pull with merge, reset to remote, or continue as-is.")
      fi
      ;;
    diverged:*:*)
      IFS=':' read -r _ ahead_count behind_count <<< "$tracking_status"
      messages+=("[git-pilot] Branch '${current_branch}' has diverged from '${remote_name}/${current_branch}' (${ahead_count} local, ${behind_count} remote). Prompt the user: rebase onto remote, merge remote, reset to remote, or continue.")
      ;;
    ahead:*)
      ahead_count="${tracking_status#ahead:}"
      messages+=("[git-pilot] Branch '${current_branch}' is ${ahead_count} commit(s) ahead of '${remote_name}/${current_branch}'. Unpushed changes.")
      ;;
  esac
fi
```

`get_branch_tracking_status()` returns: `up-to-date`, `ahead:N`, `behind:N`, `diverged:A:B`, or `no-remote`.

### 3c. Detached HEAD -- inside branch detection, when `current_branch` is empty

```bash
if [[ -z "$current_branch" ]]; then
  head_sha=$(git rev-parse --short HEAD 2>/dev/null)
  prev_branch=$(git reflog show --format='%gs' | grep -m1 'checkout: moving from' | \
    sed 's/checkout: moving from \([^ ]*\) to .*/\1/')
  if [[ -n "$prev_branch" ]]; then
    messages+=("[git-pilot] Detached HEAD at ${head_sha}. Previous branch was '${prev_branch}'. Prompt the user: return to '${prev_branch}', create a new branch from HEAD, or continue in detached state.")
  else
    messages+=("[git-pilot] Detached HEAD at ${head_sha}. Prompt the user: create a new branch from HEAD or continue in detached state.")
  fi
fi
```

### 3d. Extended state init -- replace existing Step 9

The v1 `init_state` call is `init_state "$SESSION_ID" "$current_branch" "$previous_branch"` (3 args). Replace with:

```bash
if [[ -n "$SESSION_ID" ]]; then
  base_branch="$default_branch"
  branch_purpose=""
  if [[ -n "$current_branch" ]] && [[ "$current_branch" != "$default_branch" ]]; then
    branch_purpose=$(derive_branch_purpose "$current_branch")
    configured_base=$(git config "branch.${current_branch}.merge" 2>/dev/null | sed 's|refs/heads/||' || true)
    if [[ -n "$configured_base" ]]; then
      base_branch="$configured_base"
    fi
  fi
  init_state "$SESSION_ID" "$current_branch" "$previous_branch" "$base_branch" "$branch_purpose"
fi
```

This requires `init_state()` in `state.sh` to accept 5 positional args (done in task 002).

## Files to Create or Modify
- plugins/git-pilot/scripts/session-start.sh (modify -- add fetch, freshness, detached HEAD, extended state init)
