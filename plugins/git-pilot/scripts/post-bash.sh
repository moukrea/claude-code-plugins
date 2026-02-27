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

cwd=$(echo "$input" | jq -r '.cwd // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')

# Only care about git commit and git push commands
if [[ -z "$command" ]] || ! echo "$command" | grep -qE 'git\s+(commit|push)'; then
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

# Agent suppression: skip push prompts for agent contexts where push is restricted
if is_agent_context "$session_id"; then
  if is_operation_agent_restricted "$config" "push"; then
    echo '{"continue": true}'
    exit 0
  fi
fi

# --- Push prompt after git commit (v1 logic) ---
if echo "$command" | grep -qE 'git\s+commit'; then
  push_on_finish=$(get_config "$config" '.remote.pushOnFinish' 'ask')
  auto_push=$(get_config "$config" '.remote.autoPush' 'false')

  if [[ "$auto_push" == "true" ]]; then
    push_on_finish="always"
  fi

  # Only prompt when mode is "ask" — "always" and "never" are handled elsewhere
  if [[ "$push_on_finish" == "ask" ]] && has_remote; then
    current_branch=$(get_current_branch)
    remote_name=$(get_config "$config" '.remote.defaultName' 'origin')

    # Check for unpushed commits
    unpushed=$(git log '@{u}..HEAD' --oneline 2>/dev/null || true)
    if ! git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      default_branch=$(get_default_branch "$config")
      unpushed=$(git log "${default_branch}..${current_branch}" --oneline 2>/dev/null || true)
    fi

    if [[ -n "$unpushed" ]]; then
      unpushed_count=$(echo "$unpushed" | wc -l | tr -d ' ')

      message="[git-pilot] ${unpushed_count} unpushed commit(s) on '${current_branch}'"

      jq -n --arg msg "$message" '{"continue": true, "additionalContext": $msg}'
      exit 0
    fi
  fi
fi

# --- Push rejection detection ---
if echo "$command" | grep -qE 'git\s+push'; then
  exit_code=$(echo "$input" | jq -r '.tool_result.exitCode // 0')
  # shellcheck disable=SC2034  # extracted per spec; reserved for future use
  stdout=$(echo "$input" | jq -r '.tool_result.stdout // empty')
  stderr=$(echo "$input" | jq -r '.tool_result.stderr // empty')

  if [[ "$exit_code" != "0" ]]; then
    if echo "$stderr" | grep -qiE 'rejected|failed to push|non-fast-forward'; then
      current_branch=$(get_current_branch)
      message="[git-pilot] Push rejected — remote has new commits on '${current_branch}'"
      jq -n --arg msg "$message" '{"continue": true, "additionalContext": $msg}'
      exit 0
    fi
  fi
fi

echo '{"continue": true}'
