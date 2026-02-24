# Module 04: Agent Teams Detection & Git Worktree Management

## Cross-References

- **Depends on `01-config-and-state.md`**: for config schema (three-tier merge via `load_config()`, `get_config()` accessor), session state schema (`/tmp/git-pilot-${SESSION_ID}.json`), and state read/write functions (`get_state_file()`, `read_state()`, `update_state()`, `write_state()` with atomic temp-file + `mv`).
- **Depends on `02-git-utils-and-network.md`**: for `get_current_branch()`, `has_remote()`, `is_git_repo()`, and `get_default_branch()` utility functions in `scripts/git-utils.sh`.
- **Referenced by `05-stash-and-robustness.md`**: stash auto-restore checks agent context before emitting prompts.

---

## 1. Agent Teams Detection (spec section 4.5)

**New file**: `scripts/agent.sh`

### 1.1 Agent Detection

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
```

Detection order: (1) `CLAUDE_SPAWNED_BY` env var non-empty (primary, set by Claude Code), (2) session state `.isAgent == true` (fallback). The env var name is Claude Code-dependent; the state-file fallback provides resilience.

### 1.2 Operation Restriction Check

```bash
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

### 1.3 Config and State

Config keys (`defaults/config.json`):

```jsonc
{
  "agentTeams": {
    "suppressPromptsForAgents": true,
    "orchestratorOnly": ["push", "mr"]
  }
}
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `agentTeams.suppressPromptsForAgents` | boolean | `true` | Suppress interactive prompts for spawned agents |
| `agentTeams.orchestratorOnly` | array | `["push", "mr"]` | Operations restricted to orchestrator agent |

Session state fields:

| Field | Type | Description |
|-------|------|-------------|
| `isAgent` | boolean | Whether this session is a spawned agent (not orchestrator) |
| `agentRole` | string\|null | `"orchestrator"`, `"implementer"`, `"validator"`, or null |
| `activeWorktrees` | array | List of `{path, branch, createdAt}` objects for worktrees created in this session |

### 1.4 Prompt Suppression

All hook scripts that emit interactive systemMessages must check agent context first:

```bash
if is_agent_context "$SESSION_ID" && \
   is_operation_agent_restricted "$CONFIG" "push"; then
  echo '{"continue": true}'
  exit 0
fi
```

**Hook-specific suppression**:

- **`post-bash.sh`**: Source `agent.sh`. After loading config, check `is_agent_context` + `is_operation_agent_restricted "$config" "push"`. If restricted, emit `{"continue": true}` and exit.
- **`post-write.sh`**: Source `agent.sh`. If `is_agent_context`, still track file changes but skip the auto-commit suggestion threshold message (`exit 0` after tracking).
- **`prompt-context.sh`**: If `is_agent_context`, emit `{"continue": true}` and exit (skip unrelated work detection).

### 1.5 Agent Suppression in `session-start.sh` and `session-stop.sh`

**`session-start.sh` — Branch Freshness**: Agents still fetch and fast-forward but log freshness to state only (no systemMessage prompt):

```bash
source "$SCRIPT_DIR/agent.sh"
if is_agent_context "$SESSION_ID"; then
  # Log to state, not messages array
  update_state "$(get_state_file "$SESSION_ID")" --arg status "$tracking_status" '.freshnessStatus = $status'
  # Still fast-forward if behind
  case "$tracking_status" in
    behind:*) git merge --ff-only "${remote_name}/${current_branch}" >/dev/null 2>&1 || true ;;
  esac
else
  # Normal interactive flow: add to messages array
  ...
fi
```

**`session-stop.sh` — Rebase/Summary**: Agents skip session summary and abort rebase silently on conflict:

```bash
source "$SCRIPT_DIR/agent.sh"
if is_agent_context "$SESSION_ID"; then
  # Attempt rebase but abort silently on conflict (no prompt)
  if [[ "$auto_rebase" == "true" ]] && [[ "$current_branch" != "$default_branch" ]]; then
    source "$SCRIPT_DIR/rebase.sh"
    drift_status=$(get_base_branch_drift "$current_branch" "$default_branch" "$remote_name")
    case "$drift_status" in
      drifted:*)
        rebase_result=$(attempt_rebase "${remote_name}/${default_branch}")
        [[ "$rebase_result" == "conflict" ]] && git rebase --abort 2>/dev/null || true ;;
    esac
  fi
  echo '{"continue": true}'; exit 0
fi
```

### 1.6 Operations and Agent Behavior Table

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

### 1.7 CLAUDE.md Behavioral Rule (Rule 10)

```markdown
## Rule 10: Agent Teams

When operating as a spawned agent (not the orchestrator):

1. Do not prompt for push, MR creation, or branch switching. These are
   orchestrator-only operations.
2. Follow commit rules normally — agents must still use proper commit format.
3. Do not run auto-commit suggestions. Commit when instructed by the orchestrator.
4. If instructed to work in a specific worktree directory, stay in that directory.
```

### 1.8 Test Scenarios

- `CLAUDE_SPAWNED_BY` set -> prompts suppressed.
- State file `isAgent: true` -> prompts suppressed.
- Neither set -> normal interactive behavior.
- Commit validation still active for agents.
- Agent session-start: freshness logged to state, no systemMessage emitted.
- Agent session-stop: rebase conflict silently aborted, no summary emitted.

---

## 2. Git Worktree Management (spec section 4.6)

**New file**: `scripts/worktree.sh`

### 2.1 Config Keys

```jsonc
{
  "worktree": {
    "enabled": true,
    "basePath": "../{{project}}-worktrees",
    "cleanupOnMerge": true
  }
}
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `worktree.enabled` | boolean | `true` | Enable worktree management for Agent Teams |
| `worktree.basePath` | string | `"../{{project}}-worktrees"` | Worktree directory pattern |
| `worktree.cleanupOnMerge` | boolean | `true` | Remove worktree after successful merge |

### 2.2 Worktree Creation

The `{{project}}` placeholder in `basePath` is replaced with the project directory name (basename of `git rev-parse --show-toplevel`). Branch names are sanitized for directory paths by replacing `/` with `-`.

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

Error message on failure: `"[git-pilot] Worktree creation failed: branch 'feat/auth' already exists. Use a different name or delete the existing branch."`

### 2.3 Worktree Removal

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

### 2.4 Worktree Registry

Registry file: `$(git rev-parse --git-dir)/git-pilot-worktrees.json` (persists across sessions). Uses `git rev-parse --git-dir` instead of hardcoded `.git` for correctness in worktree contexts where `.git` is a file.

Schema: `{"worktrees": [{path, branch, baseBranch, createdAt, createdBy, status}]}` (see spec section 3.3 for full example).

```bash
WORKTREE_REGISTRY="$(git rev-parse --git-dir)/git-pilot-worktrees.json"

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

All registry writes use atomic temp-file + `mv` pattern (same as state writes).

### 2.5 Worktree Merge Back

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

### 2.6 Worktree Cleanup in `session-stop.sh`

After MR/push, before state cleanup. Iterates active worktrees; removes those whose branch is merged into the default branch, unregisters stale entries where the directory no longer exists, and reports remaining active worktrees. See spec section 5.1.4 for full code.

### 2.7 Invariants and Dependencies

A half-created worktree MUST be cleaned up. Every function that starts a multi-step git operation must have cleanup logic in its error path. Required: `git` >= 2.30, `jq` >= 1.6.

### 2.8 Test Scenarios

- Worktree created -> registered in registry.
- Worktree removed -> unregistered from registry.
- Worktree merge -> branch merged, worktree cleaned up.
- Worktree directory already exists -> error reported.
