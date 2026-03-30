#!/bin/sh
set -eu

# PostToolUse hook: reads real rate limit data and preemptively switches.
# Runs async to avoid slowing down tool execution.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="${SCRIPT_DIR}/claude-switcher.sh"

AUTO_SWITCH_CONFIG="${HOME}/.claude-switcher/auto-switch.json"
if [ ! -f "$AUTO_SWITCH_CONFIG" ]; then
    exit 0
fi

enabled=$(jq -r '.enabled // false' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
if [ "$enabled" != "true" ]; then
    exit 0
fi

sh "$CLI" check-limits 2>/dev/null || true

exit 0
