# git-pilot v2 — Technical Specification

## 1. Overview

git-pilot v2 is a major upgrade to the existing Claude Code plugin that automates git workflows. While v1 handles branch creation, commit formatting, push prompts, and MR creation, it leaves significant gaps: users must drop into a separate terminal for fetching, rebasing, conflict resolution, stash management, and multi-agent coordination.

v2 closes every gap so the user never runs a git command outside Claude Code. The plugin remains Bash-only (hook scripts) with Markdown skills and a JSON config system. It integrates with Claude Code's hook lifecycle (SessionStart, PreToolUse, PostToolUse, Stop) and adds awareness of Agent Teams for parallel work.

### Primary use cases

1. Start a session on a stale branch and have it automatically fetched and fast-forwarded.
2. Finish work and have the plugin rebase onto an updated base branch before pushing.
3. Encounter rebase or merge conflicts and get guided resolution with contextual recommendations.
4. Start working on something unrelated to the current branch and get prompted to switch branches.
5. Run multiple agents in parallel via Agent Teams with isolated git worktrees.
6. Switch branches without manually stashing and restoring uncommitted changes.

### Target platforms

Linux, macOS. Any environment where Claude Code runs with `git`, `jq`, and optionally `gh`/`glab`.

### Key non-goals

- **Not a git GUI.** The plugin augments Claude's git operations via hooks and behavioral rules; it does not render diffs visually.
- **Not a CI system.** It does not run tests, linters, or builds. It manages git state only.
- **No interactive rebase.** Rebase operations are non-interactive (`git rebase`, not `git rebase -i`). Claude resolves conflicts via file edits, not an interactive TUI.
- **No submodule management.** Git submodules are out of scope.

---

## 2. Architecture

### 2.1 Component Overview

```
┌─────────────────────────────────────────────────────────┐
│                     Claude Code                          │
│                                                          │
│  ┌──────────┐  ┌────────────┐  ┌──────────┐            │
│  │ CLAUDE.md │  │ Hook Scripts│  │  Skills  │            │
│  │ (rules)   │  │ (bash)      │  │  (md)    │            │
│  └────┬─────┘  └──────┬─────┘  └────┬─────┘            │
│       │               │              │                   │
│       └───────┬───────┘──────────────┘                   │
│               │                                          │
│        ┌──────┴──────┐                                   │
│        │  Shared Libs │                                   │
│        │ config.sh    │                                   │
│        │ git-utils.sh │                                   │
│        │ state.sh     │                                   │
│        │ rebase.sh    │  ← NEW                           │
│        │ worktree.sh  │  ← NEW                           │
│        │ agent.sh     │  ← NEW                           │
│        └──────┬──────┘                                   │
│               │                                          │
│        ┌──────┴──────┐                                   │
│        │  State Files │                                   │
│        │ /tmp/git-    │                                   │
│        │ pilot-*.json │                                   │
│        └─────────────┘                                   │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

1. **SessionStart**: `session-start.sh` → fetch remote → detect branch freshness → emit systemMessage with branch status and context.
2. **UserPromptSubmit** (NEW): `prompt-context.sh` → gather branch context (name, recent commits) → emit systemMessage for Claude's unrelated-work assessment.
3. **PreToolUse (Bash)**: `pre-commit.sh` → validate commit messages, enforce branch protection, detect branch creation.
4. **PostToolUse (Write|Edit)**: `post-write.sh` → track file changes for auto-commit suggestions.
5. **PostToolUse (Bash)**: `post-bash.sh` → detect push rejection, prompt for push, handle post-rebase state.
6. **Stop**: `session-stop.sh` → drift detection, optional rebase, summary, push/MR workflow, worktree cleanup.

### 2.3 New Shared Libraries

| File | Purpose |
|------|---------|
| `scripts/rebase.sh` | Rebase operations, conflict detection, resolution helpers |
| `scripts/worktree.sh` | Worktree creation, removal, listing, registry management |
| `scripts/agent.sh` | Agent Teams detection, prompt suppression logic |

### 2.4 Key Technology Choices

- **Bash-only hooks**: Required by Claude Code's hook execution model. All hook scripts are Bash.
- **jq for JSON**: All config, state, and hook I/O is JSON. `jq` is the only parser.
- **Atomic state writes**: All state file updates use `write_state()` (temp file + `mv`) from v1.
- **git worktrees**: Native git feature for parallel working directories. No third-party tools.

---

## 3. Data Model

### 3.1 Configuration Schema

The configuration uses a three-tier merge: plugin defaults → global (`~/.claude/git-pilot.json`) → local (`.claude/git-pilot.json`). Local overrides global, global overrides defaults. The merge is a shallow recursive merge via `jq -s '.[0] * .[1]'`.

#### 3.1.1 Complete v2 Defaults (`defaults/config.json`)

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

#### 3.1.2 Backward Compatibility: `protectDefaultBranch`

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

#### 3.1.3 New Config Keys Reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `git.autoFetch` | boolean | `true` | Run `git fetch` on session start |
| `git.fetchRetries` | integer | `2` | Number of retry attempts on fetch failure |
| `git.fetchRetryDelaySec` | integer | `3` | Seconds between fetch retries |
| `git.protectDefaultBranch` | string | `"warn"` | `"warn"` / `"block"` / `"off"` — was boolean in v1 |
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

### 3.2 Session State Schema

State files are stored at `/tmp/git-pilot-${SESSION_ID}.json`. v2 extends the v1 schema:

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

New fields (v2):

| Field | Type | Description |
|-------|------|-------------|
| `baseBranch` | string | The branch this feature branch was created from or targets for MR |
| `branchPurpose` | string | Human-readable purpose derived from branch name (e.g., `"add dark mode"` from `feat/add-dark-mode`) |
| `lastFetchAt` | string\|null | ISO timestamp of last `git fetch` in this session |
| `isAgent` | boolean | Whether this session is a spawned agent (not orchestrator) |
| `agentRole` | string\|null | `"orchestrator"`, `"implementer"`, `"validator"`, or null |
| `activeWorktrees` | array | List of `{path, branch, createdAt}` objects for worktrees created in this session |
| `stashRefs` | array | List of `{ref, branch, message, createdAt}` for stashes created by git-pilot |

### 3.3 Worktree Registry

For multi-session worktree tracking, a registry file is stored at `.git/git-pilot-worktrees.json`:

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

This registry persists across sessions, unlike session state files which are cleaned up on session stop.

---

## 4. Feature Specifications

### 4.1 Branch Freshness Detection

**Trigger**: SessionStart hook (`session-start.sh`)

**Preconditions**: Repository has at least one remote. `git.autoFetch` is `true`.

**Behavior**:

1. Run `git fetch ${remote_name}` with retry logic (see §4.10).
2. Record `lastFetchAt` in session state.
3. Determine the current branch's tracking status:

```bash
# In git-utils.sh
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

4. Emit systemMessage based on status:

| Status | Action | Message |
|--------|--------|---------|
| `up-to-date` | None | No message |
| `behind:N` | Auto fast-forward | `"[git-pilot] Branch '${branch}' was ${N} commit(s) behind '${remote}/${branch}'. Fast-forwarded to latest."` |
| `behind:N` (ff fails) | Warn | `"[git-pilot] Branch '${branch}' is ${N} commit(s) behind '${remote}/${branch}' but fast-forward failed. Prompt the user: pull with merge, reset to remote, or continue as-is."` |
| `ahead:N` | Inform | `"[git-pilot] Branch '${branch}' is ${N} commit(s) ahead of '${remote}/${branch}'. Unpushed changes."` |
| `diverged:A:B` | Warn | `"[git-pilot] Branch '${branch}' has diverged from '${remote}/${branch}' (${A} local, ${B} remote). Prompt the user: rebase onto remote, merge remote, reset to remote, or continue."` |
| `no-remote` | Inform | No message (new branch, not yet pushed) |

5. For fast-forward (behind with no local changes):

```bash
if git merge --ff-only "${remote_branch}" >/dev/null 2>&1; then
  # Success — emit fast-forward message
else
  # Cannot fast-forward — emit warning with options
fi
```

**Edge cases**:
- If `git.autoFetch` is `false`, skip fetch entirely. Still check local vs. tracking branch status if tracking info exists.
- If no remote exists, skip all freshness checks.
- If the branch has no tracking branch (new local branch), skip comparison.
- If fetch fails after all retries, emit a warning and continue without freshness data (see §4.10).

### 4.2 Base Branch Drift Detection

**Trigger**: Before push or MR creation. Called from `/finish` skill, `session-stop.sh`, and `post-bash.sh` (on push commands).

**Preconditions**: On a feature branch (not default branch). Remote exists. `rebase.autoRebaseBeforePush` is `true`.

**Behavior**:

```bash
# In git-utils.sh
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

**Decision flow**:

1. If `no-drift`: proceed with push/MR.
2. If `drifted:N`:
   a. Emit: `"[git-pilot] Base branch '${base}' has ${N} new commit(s) since this branch diverged. Rebasing '${current}' onto '${remote}/${base}'..."`
   b. Attempt rebase (see §4.3).
   c. If rebase succeeds: emit `"[git-pilot] Rebase succeeded cleanly. Ready to push."` and continue.
   d. If rebase has conflicts: handle per `rebase.conflictStrategy` (see §4.3).
3. If `no-common-ancestor`: emit warning: `"[git-pilot] Cannot determine common ancestor between '${current}' and '${base}'. Skipping rebase. Push may require manual review."` Proceed with push.

**Base branch determination**:

The base branch is determined in order:
1. From session state `baseBranch` field (set when branch was created via `/branch` skill).
2. From git tracking: `git config branch.${current}.merge` → strip `refs/heads/`.
3. Fall back to `git.defaultBranch` from config.

### 4.3 Intelligent Rebase and Conflict Resolution

**New library**: `scripts/rebase.sh`

#### 4.3.1 Rebase Execution

```bash
# In rebase.sh
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

#### 4.3.2 Conflict Detection and Reporting

```bash
# In rebase.sh
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

#### 4.3.3 Conflict Resolution Messages

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

**Recommendation heuristics**:

| Conflict type | Recommendation |
|--------------|----------------|
| `deleted-by-us` | `"File was deleted locally but modified on base. If the deletion was intentional, accept ours (delete). Otherwise, accept theirs."` |
| `deleted-by-them` | `"File was deleted on base but modified locally. If your changes are still needed, accept ours. Otherwise, accept theirs (delete)."` |
| `both-modified`, 1 region | `"Single conflict region — likely a small overlap. Manual review recommended."` |
| `both-modified`, >3 regions | `"Multiple conflict regions — significant concurrent changes. Manual review required."` |

#### 4.3.4 Conflict Strategy Handling

Based on `rebase.conflictStrategy`:

| Strategy | Behavior |
|----------|----------|
| `"prompt"` | Emit conflict details and prompt user for resolution choice (default) |
| `"abort"` | Immediately abort rebase: `git rebase --abort`. Emit: `"[git-pilot] Rebase aborted due to conflicts. Push without rebase."` |
| `"merge-fallback"` | Abort rebase, attempt merge instead: `git rebase --abort && git merge ${target}`. If merge also conflicts, fall back to `"prompt"` behavior |

#### 4.3.5 Force Push Handling

After a successful rebase that rewrites history (branch was previously pushed), a force push is needed:

```bash
# In rebase.sh
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

Based on `rebase.allowForcePush`:

| Setting | Behavior |
|---------|----------|
| `"ask"` | Emit: `"[git-pilot] Rebase rewrote history. Force push required. Prompt the user: force push (git push --force-with-lease) or abort."` |
| `"never"` | Emit: `"[git-pilot] Rebase rewrote history but force push is disabled. The rebase changes are local only. Push manually if needed."` |
| `"always"` | Use `git push --force-with-lease` automatically. Emit: `"[git-pilot] Force-pushed '${branch}' to '${remote}/${branch}' after rebase."` |

Always use `--force-with-lease` (never bare `--force`) for safety.

#### 4.3.6 Push Rejection Handling

When `post-bash.sh` detects a failed `git push` (exit code non-zero, stderr contains "rejected" or "failed to push"):

```
[git-pilot] Push rejected — remote '${remote}/${branch}' has new commits.
Prompt the user:
1. Pull and rebase, then retry push (`git pull --rebase && git push`)
2. Force push with lease (`git push --force-with-lease`) — overwrites remote changes
3. Pull and merge (`git pull`) — creates a merge commit
4. Cancel
```

### 4.4 Unrelated Work Detection

**Mechanism**: CLAUDE.md behavioral rule + session state context. No additional hook required.

**Preconditions**: On a feature branch (not default branch). `branch.unrelatedWorkDetection` is `true`. Branch has at least one commit.

**CLAUDE.md Rule** (new Rule 7):

```markdown
## Rule 7: Unrelated work detection

Before starting work on a new user request, assess whether the request is related
to the current branch's purpose:

1. **Branch name**: Parse the branch name for semantic meaning. For example,
   `feat/add-dark-mode` implies work on dark mode; `fix/login-timeout` implies
   fixing a login timeout bug.
2. **Recent commits**: Review the commit log on this branch for scope context.
3. **Assessment**: If the user's request is clearly unrelated to the branch's
   purpose (different feature, different bug, different module), prompt the user:

   "This work appears unrelated to the current branch (`<branch-name>`).
   Options:
   1. Create a new branch from `<default-branch>` (recommended — keeps branches focused)
   2. Create a new branch from the current branch (if this work depends on current changes)
   3. Continue on this branch"

4. **When NOT to prompt**: Do not prompt for closely related work (e.g., fixing
   a bug discovered while implementing a feature on the same branch), for work
   on the default branch, or for branches with no commits yet.
5. **If the user chooses to create a new branch**: Follow the branch switch
   workflow (see Rule 8).
```

**Branch purpose derivation** (stored in session state at init):

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

The session-start.sh script stores `branchPurpose` in state and includes it in its systemMessage so Claude has context for the entire session.

### 4.5 Agent Teams Detection and Prompt Suppression

**New library**: `scripts/agent.sh`

#### 4.5.1 Agent Detection

```bash
# In agent.sh
is_agent_context() {
  # Primary: check Claude Code spawned-by indicator
  if [[ -n "${CLAUDE_SPAWNED_BY:-}" ]]; then
    return 0
  fi

  # Secondary: check for agent role in session state
  local session_id="${1:-}"
  if [[ -n "$session_id" ]]; then
    local state_file
    state_file=$(get_state_file "$session_id")
    local state
    state=$(read_state "$state_file")
    local is_agent
    is_agent=$(echo "$state" | jq -r '.isAgent // false')
    if [[ "$is_agent" == "true" ]]; then
      return 0
    fi
  fi

  return 1
}

# Check if a specific operation should be suppressed for agents
is_operation_agent_restricted() {
  local config="$1"
  local operation="$2"  # "push", "mr", "branch-prompt", etc.

  local suppress
  suppress=$(get_config "$config" '.agentTeams.suppressPromptsForAgents' 'true')

  if [[ "$suppress" != "true" ]]; then
    return 1  # Not suppressed
  fi

  # Check if this specific operation is orchestrator-only
  local restricted
  restricted=$(echo "$config" | jq -r --arg op "$operation" \
    '.agentTeams.orchestratorOnly // ["push", "mr"] | map(select(. == $op)) | length')

  if [[ "$restricted" -gt 0 ]]; then
    return 0  # Restricted to orchestrator
  fi

  return 1
}
```

#### 4.5.2 Prompt Suppression

All hook scripts that emit interactive systemMessages must check agent context:

```bash
# Pattern used in all hooks before emitting interactive prompts
if is_agent_context "$SESSION_ID" && \
   is_operation_agent_restricted "$CONFIG" "push"; then
  # Agent mode — suppress prompt, exit silently
  echo '{"continue": true}'
  exit 0
fi
```

**Operations and their agent behavior**:

| Operation | Orchestrator | Agent |
|-----------|-------------|-------|
| Branch creation prompt | Interactive | Suppressed |
| Push prompt after commit | Interactive | Suppressed |
| MR creation | Interactive | Suppressed |
| Commit validation | Active | Active (agents must also follow commit rules) |
| Auto-commit suggestions | Active | Suppressed |
| Rebase/conflict prompts | Interactive | Suppressed (abort rebase silently) |
| Session summary | Active | Suppressed |
| Branch freshness warnings | Active | Log to state only (no prompt) |

### 4.6 Git Worktree Management

**New library**: `scripts/worktree.sh`

#### 4.6.1 Worktree Creation

```bash
# In worktree.sh
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

  # Sanitize branch name for directory path
  local dir_name
  dir_name=$(echo "$branch_name" | tr '/' '-')
  local worktree_path="${base_path}/${dir_name}"

  # Create parent directory
  mkdir -p "$(dirname "$worktree_path")"

  # Create worktree
  local output
  if output=$(git worktree add "$worktree_path" -b "$branch_name" "$base_branch" 2>&1); then
    # Register in worktree registry
    register_worktree "$worktree_path" "$branch_name" "$base_branch" "$session_id"
    echo "$worktree_path"
    return 0
  else
    echo "error:${output}" >&2
    return 1
  fi
}
```

#### 4.6.2 Worktree Removal

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

#### 4.6.3 Worktree Registry

```bash
WORKTREE_REGISTRY=".git/git-pilot-worktrees.json"

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

list_worktrees() {
  if [[ -f "$WORKTREE_REGISTRY" ]]; then
    cat "$WORKTREE_REGISTRY"
  else
    echo '{"worktrees":[]}'
  fi
}
```

#### 4.6.4 Worktree Merge Back

```bash
merge_worktree_branch() {
  local worktree_path="$1"
  local target_branch="$2"
  local config="$3"

  # Get the worktree's branch
  local wt_branch
  wt_branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null)

  if [[ -z "$wt_branch" ]]; then
    echo "error:cannot-determine-branch"
    return 1
  fi

  # Switch to target branch in main worktree
  git checkout "$target_branch" 2>/dev/null || return 1

  # Attempt merge
  local merge_output
  if merge_output=$(git merge "$wt_branch" --no-edit 2>&1); then
    echo "success"

    # Cleanup if configured
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

### 4.7 Stash Management

**Modified file**: `scripts/git-utils.sh`

#### 4.7.1 Auto-stash on Branch Switch

When `branch.autoStashOnSwitch` is `true` and a branch switch is detected in `pre-commit.sh` (which also intercepts branch commands):

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

#### 4.7.2 Auto-restore on Branch Switch

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

#### 4.7.3 Messages

| Event | Message |
|-------|---------|
| Auto-stash on switch | `"[git-pilot] Stashed uncommitted changes on '${branch}' before switching."` |
| Auto-restore on return | `"[git-pilot] Restored stashed changes on '${branch}'."` |
| Restore failed (conflicts) | `"[git-pilot] Could not auto-restore stash on '${branch}' — conflicts detected. Run 'git stash pop' manually to resolve."` |

### 4.8 Detached HEAD Recovery

**Trigger**: `session-start.sh`, when `get_current_branch` returns empty.

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

### 4.9 Protected Branch Enforcement (Enhanced)

**Modified file**: `scripts/pre-commit.sh`

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

### 4.10 Network Error Handling

**Modified file**: `scripts/git-utils.sh`

```bash
# In git-utils.sh
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

Messages:

| Event | Message |
|-------|---------|
| Fetch failed, retrying | (no message — retries are silent) |
| All retries exhausted | `"[git-pilot] Warning: Could not fetch from '${remote}' after ${retries} attempts. Network may be unavailable. Proceeding without remote sync."` |
| Push failed (network) | `"[git-pilot] Push to '${remote}/${branch}' failed. Check network connectivity and try again."` |

---

## 5. External Interfaces

### 5.1 Hook Scripts

#### 5.1.1 Updated hooks.json

```json
{
  "description": "git-pilot: Automated git workflow management",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/prompt-context.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/pre-commit.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/post-write.sh",
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/post-bash.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/session-stop.sh",
            "timeout": 45
          }
        ]
      }
    ]
  }
}
```

**Changes from v1**:
- SessionStart timeout: 15 → 30 (to accommodate fetch + freshness check)
- PostToolUse Bash timeout: 10 → 15 (to accommodate push rejection detection + rebase)
- Stop timeout: 30 → 45 (to accommodate drift detection + rebase + MR)
- NEW: UserPromptSubmit hook for branch context (5s timeout)

#### 5.1.2 New Script: `prompt-context.sh`

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

if [[ -z "$cwd" ]]; then
  echo '{"continue": true}'
  exit 0
fi

cd "$cwd" 2>/dev/null || { echo '{"continue": true}'; exit 0; }

if ! is_git_repo; then
  echo '{"continue": true}'
  exit 0
fi

config=$(load_config "$cwd")

# Check if unrelated work detection is enabled
detection_enabled=$(get_config "$config" '.branch.unrelatedWorkDetection' 'true')
if [[ "$detection_enabled" != "true" ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Skip if agent context
if is_agent_context "$session_id"; then
  echo '{"continue": true}'
  exit 0
fi

current_branch=$(get_current_branch)
default_branch=$(get_default_branch "$config")

# Skip if on default branch or no branch (detached HEAD)
if [[ -z "$current_branch" ]] || [[ "$current_branch" == "$default_branch" ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Check if branch has commits
commit_count=$(git rev-list --count "${default_branch}..${current_branch}" 2>/dev/null || echo "0")
if [[ "$commit_count" == "0" ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Gather context
branch_purpose=$(derive_branch_purpose "$current_branch")
recent_commits=$(git log "${default_branch}..${current_branch}" --oneline --no-decorate -5 2>/dev/null || true)

message="[git-pilot] Branch context: '${current_branch}' (${branch_purpose}). ${commit_count} commit(s). Recent: ${recent_commits}"

jq -n --arg msg "$message" '{"continue": true, "systemMessage": $msg}'
```

#### 5.1.3 Modified Script: `session-start.sh`

Key additions to existing session-start.sh:

1. **Fetch remote** (after git init check, before branch detection):

```bash
# After Step 6 (git init check), before Step 7 (branch detection):

# Step 6.5: Fetch remote
if is_git_repo && has_remote; then
  auto_fetch=$(get_config "$CONFIG" '.git.autoFetch' 'true')
  remote_name=$(get_config "$CONFIG" '.remote.defaultName' 'origin')

  if [[ "$auto_fetch" == "true" ]]; then
    if ! fetch_with_retry "$remote_name" "$CONFIG"; then
      messages+=("[git-pilot] Warning: Could not fetch from '${remote_name}'. Proceeding without remote sync.")
    fi
  fi
fi
```

2. **Branch freshness check** (after branch detection):

```bash
# After getting current_branch:
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
      messages+=("[git-pilot] Branch '${current_branch}' has diverged from '${remote_name}/${current_branch}' (${ahead_count} ahead, ${behind_count} behind). Prompt the user: rebase onto remote, merge remote, reset to remote, or continue.")
      ;;
    ahead:*)
      ahead_count="${tracking_status#ahead:}"
      messages+=("[git-pilot] ${ahead_count} unpushed commit(s) on '${current_branch}'.")
      ;;
    # up-to-date and no-remote: no message
  esac
fi
```

3. **Detached HEAD detection** (in branch detection):

```bash
if [[ -z "$current_branch" ]]; then
  # Detached HEAD handling (see §4.8)
fi
```

4. **Extended state init** (replace Step 9):

```bash
if [[ -n "$SESSION_ID" ]]; then
  base_branch="$default_branch"
  branch_purpose=""
  if [[ -n "$current_branch" ]] && [[ "$current_branch" != "$default_branch" ]]; then
    branch_purpose=$(derive_branch_purpose "$current_branch")
    # Try to detect base branch from tracking config
    configured_base=$(git config "branch.${current_branch}.merge" 2>/dev/null | sed 's|refs/heads/||' || true)
    if [[ -n "$configured_base" ]]; then
      base_branch="$configured_base"
    fi
  fi
  init_state "$SESSION_ID" "$current_branch" "$previous_branch" "$base_branch" "$branch_purpose"
fi
```

#### 5.1.4 Modified Script: `session-stop.sh`

Key additions:

1. **Drift detection before push/MR** (after work summary, before push workflow):

```bash
# After section 1 (work summary), before section 2 (push workflow):

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
      # no-drift, no-common-ancestor: no action
    esac
  fi
fi
```

2. **Worktree cleanup** (after MR/push, before state cleanup):

```bash
# 3.5: Worktree cleanup
source "$SCRIPT_DIR/worktree.sh"
registry=$(list_worktrees)
active_count=$(echo "$registry" | jq '.worktrees | length')

if [[ "$active_count" -gt 0 ]]; then
  cleanup_on_merge=$(get_config "$config" '.worktree.cleanupOnMerge' 'true')
  if [[ "$cleanup_on_merge" == "true" ]]; then
    # Clean up merged worktrees
    echo "$registry" | jq -r '.worktrees[] | select(.status == "active") | .path' | \
    while IFS= read -r wt_path; do
      if [[ -d "$wt_path" ]]; then
        wt_branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || true)
        # Check if branch is merged into default
        if [[ -n "$wt_branch" ]] && git branch --merged "$default_branch" | grep -q "$wt_branch"; then
          remove_worktree "$wt_path" "false"
        fi
      else
        # Worktree directory gone, just unregister
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

#### 5.1.5 Modified Script: `post-bash.sh`

Key additions:

1. **Agent suppression**:

```bash
source "$SCRIPT_DIR/agent.sh"

# After loading config, before checking for push:
if is_agent_context "$session_id"; then
  if is_operation_agent_restricted "$config" "push"; then
    echo '{"continue": true}'
    exit 0
  fi
fi
```

2. **Push rejection detection** (new, after existing push prompt logic):

```bash
# Detect push rejection from the command output
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

#### 5.1.6 Modified Script: `post-write.sh`

Agent suppression:

```bash
source "$SCRIPT_DIR/agent.sh"

# After loading config:
if is_agent_context "$session_id"; then
  # Still track file changes but don't emit commit suggestions
  # (tracking code runs, but skip the threshold message)
  exit 0
fi
```

#### 5.1.7 Modified Script: `pre-commit.sh`

Key additions:

1. **Branch switch detection with auto-stash**:

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

2. **Enhanced protected branch blocking** (see §4.9).

### 5.2 Skills

#### 5.2.1 Existing Skills (Modified)

**`/branch`**: Add `baseBranch` recording to session state after branch creation. Emit the new branch's purpose in the confirmation message.

Add after Step 4:

```markdown
## Step 5: Record Branch Context

After creating the branch, note the base branch (the branch you were on before switching)
and the branch purpose (derived from the description). These are used for unrelated work
detection and drift checks.
```

**`/finish`**: Add drift detection before push (see §4.2). The skill should call the same drift detection logic as `session-stop.sh`.

Add between Step 1 and Step 2:

```markdown
## Step 1.5: Check Base Branch Drift

Before pushing, check if the base branch has advanced:

1. Run `git fetch <remote> <defaultBranch>`.
2. Check for new commits on the base branch since this branch diverged.
3. If the base has new commits and `rebase.autoRebaseBeforePush` is `true`:
   - Attempt `git rebase <remote>/<defaultBranch>`.
   - If rebase succeeds: continue to push.
   - If rebase has conflicts: present conflict details and options to the user.
4. If force push is needed after rebase, follow `rebase.allowForcePush` policy.
```

**`/summary`**: No changes needed.

**`/configure`**: Add all new config keys to the reference table.

Add to the reference table:

```markdown
| "Fetch remote on session start" | `git.autoFetch: true` |
| "Block commits to main" | `git.protectDefaultBranch: "block"` |
| "Don't warn about main branch commits" | `git.protectDefaultBranch: "off"` |
| "Disable unrelated work detection" | `branch.unrelatedWorkDetection: false` |
| "Don't auto-stash on branch switch" | `branch.autoStashOnSwitch: false` |
| "Don't auto-rebase before push" | `rebase.autoRebaseBeforePush: false` |
| "Never force push" | `rebase.allowForcePush: "never"` |
| "Always force push after rebase" | `rebase.allowForcePush: "always"` |
| "Use merge when rebase conflicts" | `rebase.conflictStrategy: "merge-fallback"` |
| "Disable worktrees" | `worktree.enabled: false` |
| "Worktrees in /tmp" | `worktree.basePath: "/tmp/{{project}}-worktrees"` |
```

#### 5.2.2 New Skills

**`/stash`** — Manual stash management.

```markdown
---
name: stash
description: Manage git stashes - save, list, apply, or drop
---

# /stash

Manage git stashes for the current repository.

## Step 1: Determine Action

If the user provided an argument after `/stash`, parse it:
- `/stash` or `/stash save` — stash current changes
- `/stash list` — list all stashes
- `/stash pop` or `/stash apply` — restore the most recent stash
- `/stash drop` — drop the most recent stash

If no argument, ask the user what they want to do.

## Step 2: Execute

### Save
1. Check for uncommitted changes. If none: "Nothing to stash."
2. Ask the user for an optional stash message.
3. Run `git stash push -m "<message>"` (or `git stash push` if no message).
4. Confirm: "Stashed changes: <stash-ref>"

### List
1. Run `git stash list`.
2. If empty: "No stashes found."
3. Present the list with index, branch, and message.

### Pop / Apply
1. Run `git stash list`. If empty: "No stashes to restore."
2. If multiple stashes, show the list and ask which one.
3. For pop: `git stash pop <ref>`. For apply: `git stash apply <ref>`.
4. If conflicts: warn the user and show conflicting files.

### Drop
1. Run `git stash list`. If empty: "No stashes to drop."
2. If multiple stashes, show the list and ask which one.
3. Confirm before dropping.
4. Run `git stash drop <ref>`.
```

**`/worktree`** — Manual worktree management.

```markdown
---
name: worktree
description: Manage git worktrees for parallel branch work
---

# /worktree

Manage git worktrees for parallel branch work.

## Step 1: Determine Action

Parse the user's intent:
- `/worktree` or `/worktree list` — list active worktrees
- `/worktree create <branch>` — create a new worktree for a branch
- `/worktree remove <path-or-branch>` — remove a worktree
- `/worktree merge <path-or-branch>` — merge a worktree's branch and clean up

If no argument, show the list of active worktrees.

## Step 2: Execute

### List
1. Read the worktree registry (`.git/git-pilot-worktrees.json`).
2. Also run `git worktree list` for system-level view.
3. Present: path, branch, base branch, creation date, status.

### Create
1. Ask for the branch name (or parse from argument).
2. Ask for the base branch (default: `git.defaultBranch`).
3. Determine the worktree path using `worktree.basePath` config.
4. Run `git worktree add <path> -b <branch> <base>`.
5. Register in the worktree registry.
6. Confirm with the worktree path.

### Remove
1. Identify the worktree by path or branch name.
2. Check for uncommitted changes in the worktree.
3. If uncommitted changes, warn and ask to confirm.
4. Run `git worktree remove <path>`.
5. Optionally delete the branch: `git branch -d <branch>`.
6. Unregister from the registry.

### Merge
1. Identify the worktree by path or branch name.
2. Get the worktree's branch and its base branch from the registry.
3. Switch main worktree to the base branch.
4. Attempt `git merge <worktree-branch> --no-edit`.
5. If conflicts: present them and ask user to resolve.
6. If `worktree.cleanupOnMerge` is `true`: remove the worktree and delete the branch.
7. Confirm the merge.
```

**`/rebase`** — Manual rebase operations.

```markdown
---
name: rebase
description: Rebase current branch onto another branch
---

# /rebase

Rebase the current branch onto a target branch.

## Step 1: Determine Target

If the user specified a target branch (e.g., `/rebase main`), use it.
Otherwise, default to the configured `git.defaultBranch`.

## Step 2: Pre-flight Checks

1. Ensure the working tree is clean. If uncommitted changes exist, ask to stash or commit first.
2. Fetch the remote target branch: `git fetch <remote> <target>`.
3. Check how many commits will be rebased: `git rev-list --count <remote>/<target>..HEAD`.
4. Show the user: "Rebasing N commit(s) onto <remote>/<target>."

## Step 3: Execute Rebase

1. Run `git rebase <remote>/<target>`.
2. If success: "Rebase completed successfully."
3. If conflicts:
   - Show conflicting files and conflict details.
   - Present resolution options:
     a. Resolve manually (edit files, then `git add <file>` and `git rebase --continue`)
     b. Accept theirs for all (`git checkout --theirs . && git add .`)
     c. Accept ours for all (`git checkout --ours . && git add .`)
     d. Abort (`git rebase --abort`)
   - After resolution, run `git rebase --continue`.

## Step 4: Handle Force Push

If the branch was previously pushed and rebase rewrote history:
1. Inform: "Rebase rewrote history. Force push is needed to update the remote."
2. Based on `rebase.allowForcePush`:
   - `"ask"`: Ask user to confirm force push.
   - `"always"`: Push with `--force-with-lease` automatically.
   - `"never"`: Inform that force push is disabled.
3. Use `git push --force-with-lease <remote> <branch>`.
```

### 5.3 CLAUDE.md Behavioral Rules

The complete v2 CLAUDE.md replaces the v1 version. Key additions:

**Rule 7**: Unrelated work detection (see §4.4 for full text).

**Rule 8**: Branch switching with stash management.

```markdown
## Rule 8: Branch switching

When switching branches (via /branch, user request, or unrelated work detection):

1. If there are uncommitted changes and `branch.autoStashOnSwitch` is `true`, stash
   them automatically before switching. Inform the user: "Stashed changes on '<branch>'."
2. After switching, check if there's a git-pilot stash for the target branch and
   restore it automatically.
3. If stash restoration fails (conflicts), inform the user and suggest manual resolution.
```

**Rule 9**: Conflict resolution guidance.

```markdown
## Rule 9: Conflict resolution

When a rebase or merge results in conflicts:

1. Read the conflicting files to understand the nature of each conflict.
2. For each conflict, provide a recommendation:
   - If only one side modified the region, recommend accepting that side.
   - If both sides modified the same lines, recommend manual review.
   - If a file was deleted on one side, explain the tradeoff.
3. Present clear options: resolve manually, accept ours, accept theirs, abort.
4. After the user resolves conflicts, continue the interrupted operation
   (`git rebase --continue` or `git merge --continue`).
```

**Rule 10**: Agent awareness.

```markdown
## Rule 10: Agent Teams

When operating as a spawned agent (not the orchestrator):

1. Do not prompt for push, MR creation, or branch switching. These are
   orchestrator-only operations.
2. Follow commit rules normally — agents must still use proper commit format.
3. Do not run auto-commit suggestions. Commit when instructed by the orchestrator.
4. If instructed to work in a specific worktree directory, stay in that directory.
```

**Updated skill reference table**:

```markdown
| Skill | When to use |
|-------|-------------|
| `/branch` | Proactively when on the default branch before making changes |
| `/finish` | When the user says they're done, or at session end |
| `/summary` | When the user asks for a recap of branch work |
| `/configure` | When the user wants to change git-pilot settings |
| `/stash` | When the user wants to manage git stashes |
| `/worktree` | When the user wants to manage git worktrees |
| `/rebase` | When the user wants to rebase the current branch |
```

---

## 6. Error Handling

### 6.1 Error Types

| Error Category | Source | Handling |
|---------------|--------|----------|
| Network failure | `git fetch`, `git push` | Retry with backoff (§4.10). Warn user after exhaustion. Continue without blocking. |
| Git operation failure | `git rebase`, `git merge`, `git stash` | Detect error type. Emit specific message. Never leave repo in broken state (abort incomplete operations). |
| Config parse failure | `jq` parsing | Fall back to defaults. Emit: `"[git-pilot] Warning: Could not parse config file. Using defaults."` |
| State file failure | `/tmp` write | Emit warning. Disable state-dependent features for this session. Do not crash. |
| Missing dependency | `git`, `jq` not installed | Emit warning at session start. Disable affected features. |

### 6.2 Invariant: Never Leave Broken State

If any git operation is interrupted or fails mid-way:
- An in-progress rebase MUST be aborted: `git rebase --abort`.
- An in-progress merge MUST be aborted: `git merge --abort`.
- A half-created worktree MUST be cleaned up.
- Stash operations that fail MUST NOT lose data (use `stash apply` before `stash drop`).

Every function that starts a multi-step git operation must have cleanup logic in its error path.

### 6.3 User-Facing Error Messages

All error messages follow the pattern: `[git-pilot] <context>: <specific error>. <suggestion>.`

Examples:
- `"[git-pilot] Rebase failed: could not apply commit abc1234. Conflicts in 2 file(s). Resolve conflicts or run 'git rebase --abort' to cancel."`
- `"[git-pilot] Worktree creation failed: branch 'feat/auth' already exists. Use a different name or delete the existing branch."`
- `"[git-pilot] Stash restore failed: conflicts in src/main.rs. Run 'git stash pop' manually to resolve."`

---

## 7. Configuration

### 7.1 Config File Locations

| Priority | Path | Scope |
|----------|------|-------|
| 1 (lowest) | `${PLUGIN_ROOT}/defaults/config.json` | Plugin defaults |
| 2 | `~/.claude/git-pilot.json` | User global |
| 3 (highest) | `${CWD}/.claude/git-pilot.json` | Project local |

### 7.2 Config Loading

The existing `config.sh` `load_config()` function handles the three-tier merge. No changes needed to the merge logic.

The `normalize_protect_default_branch()` function (§3.1.2) must be called wherever `git.protectDefaultBranch` is read, to handle the boolean → string migration.

### 7.3 Complete Config Key Reference

See §3.1.1 for the full defaults file. See §3.1.3 for the new keys reference table.

---

## 8. Testing Strategy

### 8.1 Unit Testing Approach

Each bash function should be testable in isolation. Use a test harness that:
1. Creates temporary git repositories with controlled state.
2. Sources the script under test.
3. Calls functions and asserts outputs.

Test framework: `bats-core` (Bash Automated Testing System).

### 8.2 Key Test Scenarios

#### Branch Freshness (§4.1)
- Branch is behind remote → auto fast-forward succeeds.
- Branch is behind remote → fast-forward fails (merge commit needed) → warning emitted.
- Branch has diverged from remote → warning with options emitted.
- Branch is ahead of remote → unpushed info emitted.
- No remote → no freshness check.
- Fetch fails → warning emitted, continues without freshness data.

#### Base Branch Drift (§4.2)
- Base branch has drifted → rebase attempted.
- Base branch has not drifted → no action.
- No common ancestor → warning emitted, push proceeds.

#### Rebase and Conflicts (§4.3)
- Clean rebase succeeds → success message.
- Rebase with conflicts → conflict details reported.
- Conflict strategy "abort" → rebase aborted immediately.
- Conflict strategy "merge-fallback" → merge attempted after rebase fails.
- Force push detection after rebase → appropriate prompt based on config.
- Push rejection detected → options presented.

#### Agent Detection (§4.5)
- `CLAUDE_SPAWNED_BY` set → prompts suppressed.
- State file `isAgent: true` → prompts suppressed.
- Neither set → normal interactive behavior.
- Commit validation still active for agents.

#### Worktree Management (§4.6)
- Worktree created → registered in registry.
- Worktree removed → unregistered from registry.
- Worktree merge → branch merged, worktree cleaned up.
- Worktree directory already exists → error reported.

#### Stash Management (§4.7)
- Auto-stash on branch switch → changes stashed, message emitted.
- Auto-restore on return → stash popped, message emitted.
- Restore fails → warning with manual instructions.

#### Protected Branch (§4.9)
- `"warn"` mode → warning emitted, commit allowed.
- `"block"` mode → commit blocked with exit code 2.
- `"off"` mode → no message.
- Boolean `true` → treated as `"warn"`.
- Boolean `false` → treated as `"off"`.

#### Config Backward Compatibility
- v1 config with `protectDefaultBranch: true` → normalized to `"warn"`.
- v1 config with `protectDefaultBranch: false` → normalized to `"off"`.
- v2 config with all new keys → works as specified.
- Missing new keys → defaults used.

### 8.3 Integration Test Scenarios

1. **Full session lifecycle**: Start session → detect stale branch → fetch → fast-forward → work → commit → detect drift → rebase → push → create MR → summary → cleanup.
2. **Conflict resolution flow**: Start session → work → attempt push → drift detected → rebase fails → conflicts shown → user resolves → rebase continues → push succeeds.
3. **Branch switching flow**: Start on feature branch → user requests unrelated work → prompt shown → user creates new branch → changes auto-stashed → new branch created → work done → switch back → stash restored.
4. **Agent teams flow**: Orchestrator creates worktree → agent works in worktree → agent commits without push prompts → orchestrator merges worktree → cleanup.

---

## 9. Build and Deployment

### 9.1 Build Commands

```bash
# Syntax check all bash scripts
for f in plugins/git-pilot/scripts/*.sh; do bash -n "$f"; done

# Lint with shellcheck
shellcheck plugins/git-pilot/scripts/*.sh

# Run tests (bats)
bats plugins/git-pilot/tests/
```

### 9.2 Dependencies

| Dependency | Version | Required |
|-----------|---------|----------|
| `bash` | >= 4.0 | Yes |
| `git` | >= 2.30 (worktree support) | Yes |
| `jq` | >= 1.6 | Yes |
| `gh` | any | Optional (GitHub PR creation) |
| `glab` | any | Optional (GitLab MR creation) |
| `shellcheck` | any | Dev only |
| `bats-core` | >= 1.0 | Dev only |

### 9.3 File Manifest

```
plugins/git-pilot/
├── .claude-plugin/
│   └── plugin.json              # Version bumped to 2.0.0
├── CLAUDE.md                    # Updated behavioral rules (10 rules)
├── README.md                    # Updated documentation
├── defaults/
│   └── config.json              # Extended with new keys
├── hooks/
│   └── hooks.json               # Updated timeouts + UserPromptSubmit hook
├── scripts/
│   ├── agent.sh                 # NEW: Agent Teams detection
│   ├── config.sh                # Minor: normalize_protect_default_branch()
│   ├── git-utils.sh             # Extended: fetch, tracking, stash, branch utils
│   ├── post-bash.sh             # Modified: agent suppression, push rejection
│   ├── post-write.sh            # Modified: agent suppression
│   ├── pre-commit.sh            # Modified: branch switch detection, block mode
│   ├── prompt-context.sh        # NEW: UserPromptSubmit branch context
│   ├── rebase.sh                # NEW: Rebase operations and conflict handling
│   ├── session-start.sh         # Modified: fetch, freshness, detached HEAD
│   ├── session-stop.sh          # Modified: drift detection, worktree cleanup
│   ├── state.sh                 # Extended: new state fields
│   └── worktree.sh              # NEW: Worktree management
├── skills/
│   ├── branch/SKILL.md          # Modified: base branch recording
│   ├── configure/SKILL.md       # Modified: new config keys
│   ├── finish/SKILL.md          # Modified: drift detection
│   ├── rebase/SKILL.md          # NEW: Manual rebase skill
│   ├── stash/SKILL.md           # NEW: Stash management skill
│   ├── summary/SKILL.md         # Unchanged
│   └── worktree/SKILL.md        # NEW: Worktree management skill
└── tests/                       # NEW: Test directory
    ├── test_helper/
    │   └── common.bash          # Shared test fixtures
    ├── branch-freshness.bats
    ├── drift-detection.bats
    ├── rebase.bats
    ├── agent-detection.bats
    ├── worktree.bats
    ├── stash.bats
    ├── protected-branch.bats
    └── config-compat.bats
```

### 9.4 Version Bump

`plugin.json` version changes from `"1.1.0"` to `"2.0.0"`. This is a major version bump because:
- `git.protectDefaultBranch` type changed from boolean to string (breaking for strict consumers).
- New behavioral rules in CLAUDE.md change default agent behavior.
- New hook (UserPromptSubmit) changes the lifecycle.

---

## 10. Implementation Notes

### 10.1 Performance Considerations

- `git fetch` is the most expensive operation (network I/O). The session-start.sh timeout is increased to 30s, but fetch should typically complete in <5s. The retry logic adds up to `fetchRetries * fetchRetryDelaySec` seconds worst-case.
- `prompt-context.sh` runs on every user prompt. It must be fast (<1s). It only runs `git rev-list --count` and `git log -5` which are fast local operations.
- `jq` is called multiple times per hook invocation for config parsing. Each call is fast (<10ms) but adds up. The existing pattern of loading config once and passing it to functions is maintained.

### 10.2 Security Considerations

- **Never bare `--force`**: Always use `--force-with-lease` for force pushes to prevent overwriting others' work.
- **No secrets in state files**: State files in `/tmp` are readable by other processes on the system. They contain only branch names, timestamps, and commit hashes — no credentials.
- **Config file permissions**: The plugin does not manage file permissions. Users should ensure `~/.claude/git-pilot.json` has appropriate permissions if it contains sensitive settings (unlikely, but noted).

### 10.3 Known Complexity Areas

- **Heredoc commit message parsing** in `pre-commit.sh`: The existing regex-based parser handles most cases but may fail on deeply nested or unusual quoting. v2 does not change this parser.
- **Branch switch detection** in `pre-commit.sh`: Detecting `git checkout <branch>` vs. `git checkout <file>` is inherently ambiguous. The regex checks for the absence of `-b` flag, but `git checkout` with a path and no `--` separator may be misdetected. This is a known limitation.
- **Stash identification**: Finding a specific stash by message is fragile if the user manually creates stashes with similar messages. The `auto_restore_stash` function searches by the exact message prefix `"git-pilot auto-stash on "`.
- **Agent detection**: The `CLAUDE_SPAWNED_BY` environment variable depends on Claude Code's implementation. If the variable name changes, the detection will need updating. The state-file fallback (`isAgent` flag) provides a manual override.

### 10.4 Backward Compatibility Guarantees

1. All v1 config files work unchanged with v2.
2. The default behavior of v2 with a v1 config is identical to v1, except:
   - `git fetch` runs on session start (new behavior, can be disabled with `git.autoFetch: false`).
   - Branch freshness information is shown (informational only, no action forced).
   - The `UserPromptSubmit` hook runs (lightweight, emits context for unrelated work detection).
3. No existing config keys are removed.
4. The `protectDefaultBranch` boolean→string migration is handled transparently.
