#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
# shellcheck source=./config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=./state.sh
source "$SCRIPT_DIR/state.sh"
# shellcheck source=./agent.sh
source "$SCRIPT_DIR/agent.sh"

# Read input from stdin
input=$(cat)

# Parse input JSON
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.cwd')
file_path=$(echo "$input" | jq -r '.tool_input.file_path')

# Load config
config=$(load_config "$cwd")

# Check if auto-commit is enabled
enabled=$(get_config "$config" '.autoCommit.enabled' 'true')
if [[ "$enabled" == "false" ]]; then
  exit 0
fi

# Get config values
threshold=$(get_config "$config" '.autoCommit.threshold' '3')
mode=$(get_config "$config" '.autoCommit.mode' 'suggest')
wip_prefix=$(get_config "$config" '.autoCommit.wipPrefix' 'wip: ')
commit_pattern=$(get_config "$config" '.commit.pattern' '{{type}}({{scope}}): {{description}}')

# Compute state file path
state_file=$(get_state_file "$session_id")

# Read current state; handle missing/unreadable state file
current_state=$(read_state "$state_file")

# Increment changeCount by 1
change_count=$(echo "$current_state" | jq '.changeCount // 0')
change_count=$((change_count + 1))

# Append file_path to modifiedFiles with deduplication
updated_state=$(echo "$current_state" | jq \
  --arg fp "$file_path" \
  --argjson cc "$change_count" \
  '.changeCount = $cc | .modifiedFiles = ((.modifiedFiles // []) + [$fp] | unique)')

# Write updated state atomically
write_state "$state_file" "$updated_state"

# Agent suppression: track changes but suppress commit suggestion
if is_agent_context "$session_id"; then
  exit 0
fi

# Check if threshold is reached
if [[ "$change_count" -lt "$threshold" ]]; then
  exit 0
fi

# Threshold reached: read modifiedFiles for the message, then reset
modified_files=$(echo "$updated_state" | jq -r '(.modifiedFiles // []) | join(", ")')

# Reset changeCount to 0 and clear modifiedFiles
reset_state=$(echo "$updated_state" | jq '.changeCount = 0 | .modifiedFiles = []')
write_state "$state_file" "$reset_state"

# Act based on mode
case "$mode" in
  suggest)
    message="[git-pilot] You've made ${threshold} file changes since the last commit. Consider committing your progress for easier rollback. Modified files: ${modified_files}"
    ;;
  auto)
    message="[git-pilot] Auto-commit threshold reached. Commit your current changes now with a descriptive message following the commit format: ${commit_pattern}"
    ;;
  silent)
    commit_msg="${wip_prefix}checkpoint after ${threshold} file changes"
    commit_output=""
    if cd "$cwd" && git add -A && commit_output=$(git commit -m "$commit_msg" 2>&1); then
      short_hash=$(git rev-parse --short HEAD)
      message="[git-pilot] Auto-committed: ${short_hash} (${commit_msg})"
    else
      message="[git-pilot] Auto-commit failed: ${commit_output}"
    fi
    ;;
  *)
    # Unknown mode, fall back to suggest
    message="[git-pilot] You've made ${threshold} file changes since the last commit. Consider committing your progress for easier rollback. Modified files: ${modified_files}"
    ;;
esac

# Output the result
jq -n --arg msg "$message" '{continue: true, systemMessage: $msg}'
