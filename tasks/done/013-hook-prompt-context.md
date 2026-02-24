# Task 013: Hook prompt-context.sh (New)

## Status
done

## Dependencies
- 003-git-utils-extensions (uses `derive_branch_purpose()` from `git-utils.sh`)
- 004-agent-library (uses `is_agent_context()` from `agent.sh` to suppress in agent contexts)

## Spec References
- spec/06-hooks-and-lifecycle.md (section 2)

## Scope
Create a new `prompt-context.sh` script that runs on the `UserPromptSubmit` hook event. It provides branch context (purpose, commit count, recent commits) as a system message on every user prompt, enabling Claude to detect when the user's request is unrelated to the current branch's purpose. Suppressed for agents and when `branch.unrelatedWorkDetection` is `false`.

## Acceptance Criteria
- [x] New file `scripts/prompt-context.sh` created with shebang `#!/usr/bin/env bash` and `set -euo pipefail`
- [x] Sources `config.sh`, `git-utils.sh`, and `agent.sh`
- [x] Reads input JSON from stdin; extracts `session_id` and `cwd`; early-exits with `{"continue": true}` if: no cwd, not a git repo, `branch.unrelatedWorkDetection` is not `true`, or `is_agent_context` returns true
- [x] Skips (early-exits) if on default branch or in detached HEAD (empty `current_branch`)
- [x] Skips if branch has no commits (`git rev-list --count "${default_branch}..${current_branch}"` is 0)
- [x] Emits system message: `"[git-pilot] Branch context: '${current_branch}' (${branch_purpose}). ${commit_count} commit(s). Recent: ${recent_commits}"`
- [x] `branch_purpose` is derived via `derive_branch_purpose "$current_branch"`; `recent_commits` are the last 5 commits via `git log "${default_branch}..${current_branch}" --oneline --no-decorate -5`

## Implementation Notes

### Full script

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

### Key details

- Config key: `.branch.unrelatedWorkDetection` (default `true`)
- `derive_branch_purpose()` is from task 003 (git-utils-extensions); it parses branch name patterns to infer purpose (e.g., `feat/add-auth` -> `"feature: add auth"`)
- The output format uses `{"continue": true, "systemMessage": $msg}` -- same pattern as other hooks
- The `UserPromptSubmit` hook type means this runs BEFORE Claude processes the user's prompt, so the branch context is injected into Claude's system context for that turn
- Timeout is 5 seconds (registered in hooks.json, task 014)

## Files to Create or Modify
- plugins/git-pilot/scripts/prompt-context.sh (new)
