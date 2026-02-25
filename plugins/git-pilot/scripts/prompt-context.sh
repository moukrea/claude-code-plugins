#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=./git-utils.sh
source "$SCRIPT_DIR/git-utils.sh"
# shellcheck source=./agent.sh
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
message="[git-pilot] You are on branch '${current_branch}' (purpose: ${branch_purpose}, ${commit_count} commit(s)). Before acting on the user's next request, assess whether the request is related to this branch's purpose. If unrelated, STOP and use AskUserQuestion to suggest creating a new branch. Recent commits: ${recent_commits}"
jq -n --arg msg "$message" '{"continue": true, "systemMessage": $msg}'
