#!/usr/bin/env bash
# post-bash-auth-check.sh — PostToolUse hook for Bash commands
#
# Detects authentication failures in command output and suggests
# using opaq to find and apply credentials.

set -euo pipefail

# Only act if opaq is available
command -v opaq >/dev/null 2>&1 || exit 0

INPUT=$(cat)

# Extract the tool result (stdout/stderr) and the original command
TOOL_RESULT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty')
TOOL_STDERR=$(echo "$INPUT" | jq -r '.tool_result.stderr // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
# shellcheck disable=SC2034  # extracted for potential future use
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exit_code // "0"')

# Combine stdout and stderr for pattern matching
COMBINED="${TOOL_RESULT}
${TOOL_STDERR}"

[ -z "$COMBINED" ] && exit 0

# Check for authentication failure patterns (case-insensitive)
AUTH_FAILURE=false

if echo "$COMBINED" | grep -qiE '(HTTP[/ ](401|403)\b|status[: ]+(401|403)\b)'; then
  AUTH_FAILURE=true
elif echo "$COMBINED" | grep -qiE 'authentication required|unauthorized|access denied|permission denied|invalid token|bad credentials|login required'; then
  AUTH_FAILURE=true
elif echo "$COMBINED" | grep -qiE 'denied: requested access to the resource is denied'; then
  AUTH_FAILURE=true
elif echo "$COMBINED" | grep -qiE 'Authentication failed|could not read Username'; then
  AUTH_FAILURE=true
fi

[ "$AUTH_FAILURE" = "false" ] && exit 0

# Infer a keyword from the command
KEYWORD="credentials"

if echo "$COMMAND" | grep -qiE 'docker|registry'; then
  KEYWORD="docker"
elif echo "$COMMAND" | grep -qiE '^\s*git\b|\.git'; then
  KEYWORD="git"
elif echo "$COMMAND" | grep -qiE '\bssh\b'; then
  KEYWORD="ssh"
elif echo "$COMMAND" | grep -qiE '\bnpm\b'; then
  KEYWORD="npm"
elif echo "$COMMAND" | grep -qoE 'https?://[^/ ]+' | head -1 | grep -qoE '[^.]+\.[^.]+$'; then
  # Extract domain from URL — e.g., api.github.com -> github
  KEYWORD=$(echo "$COMMAND" | grep -oE 'https?://[^/ ]+' | head -1 | sed 's|https\?://||' | awk -F. '{if (NF>=2) print $(NF-1); else print $1}')
fi

jq -n --arg keyword "$KEYWORD" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    systemMessage: ("[opaq] Authentication failure detected. Search opaq for relevant credentials: `opaq search " + $keyword + "`. Then retry the command using `opaq run -- <command>` with the appropriate {{SECRET_NAME}} placeholder.")
  }
}'
