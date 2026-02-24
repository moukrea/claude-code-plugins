# 06 — Hooks and Lifecycle

## Cross-References

- **`01-config-and-state.md`** — `load_config`, `get_config`, `get_state_file`, `read_state`, `write_state`, `update_state`, `init_state`; state fields `baseBranch`, `branchPurpose`, `lastFetchAt`, `isAgent`, `agentRole`, `activeWorktrees`, `stashRefs`.
- **`02-git-utils-and-network.md`** — `is_git_repo`, `has_remote`, `get_current_branch`, `get_default_branch`, `is_on_default_branch`, `has_uncommitted_changes`, `get_branch_tracking_status`, `get_base_branch_drift`, `fetch_with_retry`, `derive_branch_purpose`, `normalize_protect_default_branch`.
- **`03-rebase-and-conflicts.md`** — `attempt_rebase`, `get_conflict_details`, `needs_force_push`, conflict strategy handling.
- **`04-agent-and-worktree.md`** — `is_agent_context`, `is_operation_agent_restricted`, `create_worktree`, `remove_worktree`, `register_worktree`, `unregister_worktree`, `list_worktrees`.
- **`05-stash-and-robustness.md`** — `auto_stash`, `auto_restore_stash`, `output_block`, `output_allow_with_message`.

## 1. Updated `hooks.json`

```json
{
  "description": "git-pilot: Automated git workflow management",
  "hooks": {
    "SessionStart": [{
      "matcher": "startup",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh",
        "timeout": 30
      }]
    }],
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/prompt-context.sh",
        "timeout": 5
      }]
    }],
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/pre-commit.sh",
        "timeout": 10
      }]
    }],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/post-write.sh",
          "timeout": 10
        }]
      },
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/post-bash.sh",
          "timeout": 15
        }]
      }
    ],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/session-stop.sh",
        "timeout": 45
      }]
    }]
  }
}
```

**Changes from v1**: SessionStart timeout 15 → 30 (fetch + freshness). PostToolUse Bash timeout 10 → 15 (push rejection + rebase). Stop timeout 30 → 45 (drift + rebase + MR). NEW: `UserPromptSubmit` hook for branch context (5s timeout).

## 2. New Script: `prompt-context.sh`

Runs on every user prompt submission. Provides branch context for unrelated work detection.

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/git-utils.sh"
source "$SCRIPT_DIR/agent.sh"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

if [[ -z "$cwd" ]]; then echo '{"continue": true}'; exit 0; fi
cd "$cwd" 2>/dev/null || { echo '{"continue": true}'; exit 0; }
if ! is_git_repo; then echo '{"continue": true}'; exit 0; fi

config=$(load_config "$cwd")

detection_enabled=$(get_config "$config" '.branch.unrelatedWorkDetection' 'true')
if [[ "$detection_enabled" != "true" ]]; then echo '{"continue": true}'; exit 0; fi
if is_agent_context "$session_id"; then echo '{"continue": true}'; exit 0; fi

current_branch=$(get_current_branch)
default_branch=$(get_default_branch "$config")

# Skip if on default branch or detached HEAD
if [[ -z "$current_branch" ]] || [[ "$current_branch" == "$default_branch" ]]; then
  echo '{"continue": true}'; exit 0
fi

# Skip if branch has no commits
commit_count=$(git rev-list --count "${default_branch}..${current_branch}" 2>/dev/null || echo "0")
if [[ "$commit_count" == "0" ]]; then echo '{"continue": true}'; exit 0; fi

branch_purpose=$(derive_branch_purpose "$current_branch")
recent_commits=$(git log "${default_branch}..${current_branch}" --oneline --no-decorate -5 2>/dev/null || true)
message="[git-pilot] Branch context: '${current_branch}' (${branch_purpose}). ${commit_count} commit(s). Recent: ${recent_commits}"
jq -n --arg msg "$message" '{"continue": true, "systemMessage": $msg}'
```

## 3. Modified Script: `session-start.sh`

### 3a. Fetch remote (insert after git init check, before branch detection)

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

### 3b. Branch freshness check (insert after getting `current_branch`)

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
    # up-to-date and no-remote: no message
  esac
fi
```

### 3c. Detached HEAD detection (inside branch detection, when `get_current_branch` returns empty)

```bash
if [[ -z "$current_branch" ]]; then
  local head_sha
  head_sha=$(git rev-parse --short HEAD 2>/dev/null)
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

### 3d. Extended state init (replace existing Step 9)

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

> **Note**: `init_state()` creates or resets the session state file (see `01-config-and-state.md` for the full definition). The 5 arguments map to session state fields: `sessionId`, `workingBranch`, `previousBranch`, `baseBranch`, and `branchPurpose`. It also sets `startTime` to the current ISO timestamp, `headAtStart` to the current HEAD SHA, and initializes counters (`changeCount: 0`, `modifiedFiles: []`, etc.).

## 4. Modified Script: `session-stop.sh`

### 4a. Drift detection (insert after work summary, before push workflow)

```bash
# 1.5: Base branch drift detection
if [[ "$session_had_changes" == "true" ]] && has_remote; then
  auto_rebase=$(get_config "$config" '.rebase.autoRebaseBeforePush' 'true')
  if [[ "$auto_rebase" == "true" ]] && [[ "$current_branch" != "$default_branch" ]]; then
    source "$SCRIPT_DIR/rebase.sh"
    drift_status=$(get_base_branch_drift "$current_branch" "$default_branch" "$remote_name")
    case "$drift_status" in
      drifted:*)
        drift_count="${drift_status#drifted:}"
        messages+=("[git-pilot] Base branch '${default_branch}' has ${drift_count} new commit(s). Rebasing '${current_branch}' onto '${remote_name}/${default_branch}'...")
        rebase_result=$(attempt_rebase "${remote_name}/${default_branch}")
        case "$rebase_result" in
          success)
            messages+=("[git-pilot] Rebase succeeded cleanly. Ready to push.")
            ;;
          conflict)
            conflict_strategy=$(get_config "$config" '.rebase.conflictStrategy' 'prompt')
            case "$conflict_strategy" in
              prompt)
                conflicts=$(get_conflict_details)
                conflict_count=$(echo "$conflicts" | jq 'length')
                conflict_files=$(echo "$conflicts" | jq -r '.[].file' | paste -sd', ')
                messages+=("[git-pilot] Rebase conflicts in ${conflict_count} file(s): ${conflict_files}. Prompt the user to resolve conflicts, abort rebase, or use merge instead.")
                ;;
              abort)
                git rebase --abort 2>/dev/null
                messages+=("[git-pilot] Rebase aborted due to conflicts. Pushing without rebase.")
                ;;
              merge-fallback)
                git rebase --abort 2>/dev/null
                if git merge "${remote_name}/${default_branch}" --no-edit 2>/dev/null; then
                  messages+=("[git-pilot] Merge with '${default_branch}' succeeded (rebase had conflicts).")
                else
                  conflicts=$(get_conflict_details)
                  conflict_count=$(echo "$conflicts" | jq 'length')
                  messages+=("[git-pilot] Both rebase and merge have conflicts in ${conflict_count} file(s). Prompt the user to resolve.")
                fi
                ;;
            esac
            ;;
        esac
        ;;
      no-drift)
        # No action needed
        ;;
      no-common-ancestor)
        messages+=("[git-pilot] Cannot determine common ancestor between '${current_branch}' and '${default_branch}'. Skipping rebase. Push may require manual review.")
        ;;
    esac
  fi
fi
```

> **Agent context**: If `is_agent_context "$session_id"` is true, skip the drift detection and rebase block entirely (agents suppress rebase/conflict prompts — abort rebase silently). Wrap the drift detection code above in:
> ```bash
> if ! is_agent_context "$session_id"; then
>   # ... drift detection and rebase code ...
> fi
> ```
> Similarly, skip the session summary output for agents. If the existing session summary section emits messages, guard it with:
> ```bash
> if ! is_agent_context "$session_id"; then
>   # ... session summary messages ...
> fi
> ```
> See `04-agent-and-worktree.md` for `is_agent_context()` and the suppression table (rebase/conflict prompts: suppressed; session summary: suppressed).

### 4b. Worktree cleanup (insert after MR/push, before state cleanup)

```bash
source "$SCRIPT_DIR/worktree.sh"
registry=$(list_worktrees)
active_count=$(echo "$registry" | jq '.worktrees | length')
if [[ "$active_count" -gt 0 ]]; then
  cleanup_on_merge=$(get_config "$config" '.worktree.cleanupOnMerge' 'true')
  if [[ "$cleanup_on_merge" == "true" ]]; then
    echo "$registry" | jq -r '.worktrees[] | select(.status == "active") | .path' | \
    while IFS= read -r wt_path; do
      if [[ -d "$wt_path" ]]; then
        wt_branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || true)
        if [[ -n "$wt_branch" ]] && git branch --merged "$default_branch" | grep -q "$wt_branch"; then
          remove_worktree "$wt_path" "false"
        fi
      else
        unregister_worktree "$wt_path"
      fi
    done
  fi
  remaining=$(list_worktrees | jq '.worktrees | length')
  if [[ "$remaining" -gt 0 ]]; then
    messages+=("[git-pilot] ${remaining} active worktree(s) remain. Use /worktree to manage them.")
  fi
fi
```

## 5. Modified Script: `post-bash.sh`

### 5a. Agent suppression (insert after loading config, before push check)

```bash
source "$SCRIPT_DIR/agent.sh"
if is_agent_context "$session_id"; then
  if is_operation_agent_restricted "$config" "push"; then
    echo '{"continue": true}'
    exit 0
  fi
fi
```

### 5b. Push rejection detection (insert after existing push prompt logic)

```bash
exit_code=$(echo "$input" | jq -r '.tool_result.exitCode // 0')
stdout=$(echo "$input" | jq -r '.tool_result.stdout // empty')
stderr=$(echo "$input" | jq -r '.tool_result.stderr // empty')
if echo "$command" | grep -qE 'git\s+push' && [[ "$exit_code" != "0" ]]; then
  if echo "$stderr" | grep -qiE 'rejected|failed to push|non-fast-forward'; then
    current_branch=$(get_current_branch)
    remote_name=$(get_config "$config" '.remote.defaultName' 'origin')
    message="[git-pilot] Push rejected — remote '${remote_name}/${current_branch}' has new commits. Prompt the user:
1. Pull and rebase, then retry push (git pull --rebase && git push)
2. Force push with lease (git push --force-with-lease)
3. Pull and merge (git pull)
4. Cancel"
    jq -n --arg msg "$message" '{"continue": true, "systemMessage": $msg}'
    exit 0
  fi
fi
```

## 6. Modified Script: `post-write.sh`

Agent suppression -- insert after loading config. Still track file changes but suppress commit suggestion messages for agents:

```bash
source "$SCRIPT_DIR/agent.sh"
if is_agent_context "$session_id"; then
  # Tracking code runs, but skip the threshold message
  exit 0
fi
```

## 7. Modified Script: `pre-commit.sh`

### 7a. Branch switch detection with auto-stash

Add to the branch creation detection section:

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

### 7b. Enhanced protected branch blocking

Replace existing default-branch warning with tri-state logic:

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
