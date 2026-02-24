#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=./git-utils.sh
source "$SCRIPT_DIR/git-utils.sh"

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Only care about git commit commands
if [[ -z "$command" ]] || ! echo "$command" | grep -qE 'git\s+commit'; then
  echo '{"continue": true}'
  exit 0
fi

if [[ -z "$cwd" ]]; then
  echo '{"continue": true}'
  exit 0
fi

cd "$cwd"

if ! is_git_repo; then
  echo '{"continue": true}'
  exit 0
fi

config=$(load_config "$cwd")
push_on_finish=$(get_config "$config" '.remote.pushOnFinish' 'ask')
auto_push=$(get_config "$config" '.remote.autoPush' 'false')

if [[ "$auto_push" == "true" ]]; then
  push_on_finish="always"
fi

# Only prompt when mode is "ask" — "always" and "never" are handled elsewhere
if [[ "$push_on_finish" != "ask" ]]; then
  echo '{"continue": true}'
  exit 0
fi

if ! has_remote; then
  echo '{"continue": true}'
  exit 0
fi

current_branch=$(get_current_branch)
remote_name=$(get_config "$config" '.remote.defaultName' 'origin')

# Check for unpushed commits
unpushed=$(git log '@{u}..HEAD' --oneline 2>/dev/null || true)
if ! git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  default_branch=$(get_default_branch "$config")
  unpushed=$(git log "${default_branch}..${current_branch}" --oneline 2>/dev/null || true)
fi

if [[ -z "$unpushed" ]]; then
  echo '{"continue": true}'
  exit 0
fi

unpushed_count=$(echo "$unpushed" | wc -l | tr -d ' ')

# Emit push prompt — CLAUDE.md instructs Claude to act on this with AskUserQuestion
message="[git-pilot] ${unpushed_count} unpushed commit(s) on '${current_branch}'. Push command: git push -u ${remote_name} ${current_branch}"

jq -n --arg msg "$message" '{"continue": true, "systemMessage": $msg}'
