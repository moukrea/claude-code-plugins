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
      messages+=("[git-pilot] On '${default_branch}' with uncommitted changes. Prompt the user: stash and create branch, commit first, or continue on '${default_branch}'.")
    else
      messages+=("[git-pilot] On default branch '${default_branch}'. Prompt the user to create a branch before making changes. Pattern: ${branch_pattern}, types: ${branch_types}.")
    fi
  fi
fi

# Step 8: Remote detection (only if we are in a git repo)
if is_git_repo; then
  if ! has_remote; then
    prompt_remote=$(get_config "$CONFIG" '.remote.promptForRemote' 'true')
    skip_remote=$(get_config "$CONFIG" '.remote.skipRemotePrompt' 'false')

    if [[ "$prompt_remote" == "true" ]] && [[ "$skip_remote" == "false" ]]; then
      messages+=("[git-pilot] No git remote configured. Prompt the user to add one or skip.")
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
