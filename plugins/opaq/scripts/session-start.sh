#!/usr/bin/env bash
# session-start.sh — SessionStart hook for the opaq plugin
#
# Checks opaq availability and emits a directive system message
# telling the agent how to use opaq for credential management.

set -euo pipefail

# Check if opaq is installed and available
if ! command -v opaq >/dev/null 2>&1; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      systemMessage: "[opaq] WARNING: opaq is not installed. Credential management via opaq is unavailable. If a task requires secrets, you will need to ask the user directly. Install opaq: https://github.com/moukrea/opaq"
    }
  }'
  exit 0
fi

# Check if opaq store is initialized (search should not error)
if ! opaq search __ping__ >/dev/null 2>&1; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      systemMessage: "[opaq] WARNING: opaq is installed but the store may not be initialized or is locked. Credential management may be unavailable. The user may need to run `opaq init` or `opaq unlock`."
    }
  }'
  exit 0
fi

jq -n '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    systemMessage: "[opaq] Secure credential manager is active. When any task requires credentials (API tokens, passwords, SSH keys, registry logins, deployment secrets), you MUST use `opaq search <keyword>` to find them and `opaq run -- <command>` with {{PLACEHOLDER}} syntax to use them. Do NOT ask the user for secrets or hardcode credentials without checking opaq first."
  }
}'
