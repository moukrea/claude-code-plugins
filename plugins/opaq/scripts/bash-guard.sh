#!/usr/bin/env bash
# bash-guard.sh — PreToolUse hook for Bash commands
#
# 1. Blocks direct access to the opaq store and OS keychain
# 2. Blocks agent use of user-only subcommands
# 3. Auto-wraps commands containing {{SECRET}} placeholders with `opaq run --`

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$COMMAND" ] && exit 0

# -- Block direct access to secrets store and keychain --------------------------
BLOCKED=(
  '.config/opaq'
  'opaq/store'
  'secret-tool'
  'org.freedesktop.secrets'
  'org.freedesktop.Secret'
  'keyctl'
  'gnome-keyring'
  'kwallet'
  'security find-generic-password'
  'security delete-generic-password'
  'security dump-keychain'
)

for pat in "${BLOCKED[@]}"; do
  if echo "$COMMAND" | grep -qi "$pat"; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Direct access to the opaq store or OS keychain is blocked. Use `opaq search <keyword>` to discover secrets, then `opaq run -- <command>` with {{SECRET_NAME}} placeholders."
      }
    }'
    exit 0
  fi
done

# -- Block user-only subcommands ------------------------------------------------
if echo "$COMMAND" | grep -qE 'opaq\s+(add|remove|edit|export|import|init|lock|unlock)\b'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "This opaq subcommand requires an interactive terminal and cannot be run by an agent. Only `search` and `run` are available."
    }
  }'
  exit 0
fi

# -- Auto-wrap commands containing {{SECRET}} placeholders ----------------------
if echo "$COMMAND" | grep -qE '\{\{[A-Za-z_][A-Za-z0-9_]*\}\}'; then
  if ! echo "$COMMAND" | grep -q 'opaq run'; then
    WRAPPED="opaq run -- $COMMAND"
    jq -n --arg cmd "$WRAPPED" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: { command: $cmd }
      }
    }'
    exit 0
  fi
fi

exit 0
