# Task 012: Hook session-stop.sh Modifications

## Status
done

## Dependencies
- 003-git-utils-extensions (uses `get_base_branch_drift()` for drift detection)
- 004-agent-library (uses `is_agent_context()` to suppress rebase/summary for agents)
- 005-rebase-library (uses `attempt_rebase()`, `get_conflict_details()` for rebase workflow)
- 006-worktree-library (uses `list_worktrees()`, `remove_worktree()`, `unregister_worktree()` for cleanup)

## Spec References
- spec/06-hooks-and-lifecycle.md (sections 4a, 4b)
- spec/05-stash-and-robustness.md (section 5 -- error handling invariants)

## Scope
Modify the existing `session-stop.sh` script to add three capabilities: (a) base branch drift detection with automatic rebase before push, respecting conflict strategy config, (b) worktree cleanup for merged branches, and (c) agent context suppression for both drift/rebase and session summary blocks.

## Acceptance Criteria
- [x] Source `agent.sh`, `rebase.sh`, and `worktree.sh` at the appropriate points in the script
- [x] Drift detection block: when `session_had_changes` is true, `has_remote`, `rebase.autoRebaseBeforePush` is `true`, and branch is not default -- call `get_base_branch_drift()` and handle `drifted:*`, `no-drift`, and `no-common-ancestor` cases
- [x] On `drifted:N`, call `attempt_rebase("${remote_name}/${default_branch}")` and handle `success` and `conflict` results; for conflicts, respect `rebase.conflictStrategy` (`prompt`/`abort`/`merge-fallback`)
- [x] Agent suppression: wrap drift detection/rebase AND session summary blocks in `if ! is_agent_context "$session_id"; then ... fi`
- [x] Worktree cleanup: after MR/push logic, iterate `list_worktrees()` active entries; remove worktrees whose branch is merged into default branch; unregister worktrees with missing paths; emit remaining count message
- [x] Drift detection is inserted AFTER work summary, BEFORE push workflow (between existing sections 1 and 2)
- [x] Worktree cleanup is inserted AFTER MR/push, BEFORE state cleanup (between existing sections 3 and 4)

## Implementation Notes

### 4a. Drift detection -- insert after work summary (section 1), before push workflow (section 2)

```bash
source "$SCRIPT_DIR/agent.sh"

if ! is_agent_context "$session_id"; then
  # Drift detection and rebase
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
fi
```

Config keys: `.rebase.autoRebaseBeforePush` (default `true`), `.rebase.conflictStrategy` (default `prompt`, values: `prompt`/`abort`/`merge-fallback`).

`get_base_branch_drift()` returns: `drifted:N`, `no-drift`, or `no-common-ancestor`.
`attempt_rebase()` returns: `success` or `conflict`.
`get_conflict_details()` returns a JSON array: `[{"file":"...","status":"..."}]`.

### Agent suppression for session summary

The existing work summary block (section 1, lines ~69-102 in v1) must also be wrapped:

```bash
if ! is_agent_context "$session_id"; then
  # ... existing work summary code ...
fi
```

### 4b. Worktree cleanup -- insert after MR/push (section 3), before state cleanup (section 4)

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

Config key: `.worktree.cleanupOnMerge` (default `true`).

## Files to Create or Modify
- plugins/git-pilot/scripts/session-stop.sh (modify -- add drift detection, worktree cleanup, agent suppression)
