#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=./git-utils.sh
source "$SCRIPT_DIR/git-utils.sh"
# shellcheck source=./state.sh
source "$SCRIPT_DIR/state.sh"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [[ -z "$CWD" ]]; then
  CWD="."
fi

cd "$CWD"

CONFIG=$(load_config "$CWD")

messages=()

# Step 5: Check dependencies
if ! command -v git >/dev/null 2>&1; then
  messages+=("[git-pilot] Warning: git is not installed. Git workflow features are disabled.")
fi

if ! command -v jq >/dev/null 2>&1; then
  messages+=("[git-pilot] Warning: jq is not installed. Configuration loading may not work correctly.")
fi

# Step 6: Git init check
if ! is_git_repo; then
  auto_init=$(get_config "$CONFIG" '.git.autoInit' 'true')
  default_branch=$(get_config "$CONFIG" '.git.defaultBranch' 'main')

  if [[ "$auto_init" == "true" ]]; then
    if git init -b "$default_branch" >/dev/null 2>&1; then
      if [[ ! -f ".gitignore" ]]; then
        touch .gitignore
      fi
      messages+=("[git-pilot] Initialized git repository with default branch '${default_branch}'.")
    else
      messages+=("[git-pilot] Warning: Failed to initialize git repository.")
    fi
  else
    messages+=("[git-pilot] Warning: Current directory is not a git repository. Run 'git init' to initialize one.")
  fi
fi

# Step 7: Branch detection (only if we are in a git repo now)
current_branch=""
default_branch=$(get_config "$CONFIG" '.git.defaultBranch' 'main')

if is_git_repo; then
  current_branch=$(get_current_branch)
  auto_create=$(get_config "$CONFIG" '.branch.autoCreate' 'true')

  if [[ "$auto_create" == "true" ]] && [[ "$current_branch" == "$default_branch" ]]; then
    branch_pattern=$(get_config "$CONFIG" '.branch.pattern' '{{type}}/{{description}}')
    branch_types=$(echo "$CONFIG" | jq -r '.branch.types // ["feat","fix","refactor","docs","test","chore","style","perf","build","ci"] | join(", ")')

    if has_uncommitted_changes; then
      messages+=("[git-pilot] You are on '${default_branch}' with uncommitted changes. Ask the user if they want to: (1) stash changes and create a new branch, (2) commit changes first, or (3) continue on the current branch.")
    else
      messages+=("[git-pilot] You are on the default branch '${default_branch}'. Before making changes, create a new branch. Use the naming pattern: ${branch_pattern}. Available types: ${branch_types}. Ask the user what they're working on to determine the branch name, or infer it from their request.")
    fi
  fi
fi

# Step 8: Remote detection (only if we are in a git repo)
if is_git_repo; then
  if ! has_remote; then
    prompt_remote=$(get_config "$CONFIG" '.remote.promptForRemote' 'true')
    skip_remote=$(get_config "$CONFIG" '.remote.skipRemotePrompt' 'false')

    if [[ "$prompt_remote" == "true" ]] && [[ "$skip_remote" == "false" ]]; then
      messages+=("[git-pilot] No git remote is configured. Ask the user if they'd like to add one (e.g., git@github.com:user/repo.git or https://github.com/user/repo.git). If they want to skip, set remoteSkipped in the session so we don't ask again.")
    fi
  fi
fi

# Step 9: Initialize session state
if [[ -n "$SESSION_ID" ]]; then
  previous_branch="$current_branch"
  init_state "$SESSION_ID" "$current_branch" "$previous_branch"
fi

# Step 10: Build and output final JSON
system_message=""
for msg in "${messages[@]+${messages[@]}}"; do
  if [[ -n "$system_message" ]]; then
    system_message="${system_message}"$'\n'"${msg}"
  else
    system_message="$msg"
  fi
done

if [[ -n "$system_message" ]]; then
  jq -n --arg msg "$system_message" '{"continue": true, "systemMessage": $msg}'
else
  jq -n '{"continue": true}'
fi

exit 0
