#!/bin/sh
set -eu

# StopFailure hook: fires when a turn ends due to API error.
# Detects rate limit errors and auto-switches to fallback profile.

SWITCHER_DIR="${HOME}/.claude-switcher"
AUTO_SWITCH_CONFIG="${SWITCHER_DIR}/auto-switch.json"
AUTO_SWITCH_STATE="${SWITCHER_DIR}/auto-switch-state.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="${SCRIPT_DIR}/claude-switcher.sh"

INPUT=$(cat)

if [ ! -f "$AUTO_SWITCH_CONFIG" ]; then
    exit 0
fi

enabled=$(jq -r '.enabled // false' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
if [ "$enabled" != "true" ]; then
    exit 0
fi

if [ -f "$AUTO_SWITCH_STATE" ]; then
    on_fb=$(jq -r '.on_fallback // false' "$AUTO_SWITCH_STATE" 2>/dev/null)
    if [ "$on_fb" = "true" ]; then
        exit 0
    fi
fi

transcript_path=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
error_info=$(echo "$INPUT" | jq -r '.error // .error_type // .message // empty' 2>/dev/null)

is_rate_limit=false

if [ -n "$error_info" ]; then
    if echo "$error_info" | grep -iqE "rate.?limit|429|overloaded|usage.?limit|too many|quota|throttl|capacity"; then
        is_rate_limit=true
    fi
fi

if [ "$is_rate_limit" = "false" ] && [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    if tail -20 "$transcript_path" 2>/dev/null | grep -iqE "rate.?limit|429|overloaded|usage.?limit|too many requests|quota exceeded|throttl|capacity"; then
        is_rate_limit=true
    fi
fi

if [ "$is_rate_limit" = "false" ]; then
    exit 0
fi

sh "$CLI" limit-hit 2>&1 || true

cat <<EOF
{"result":"Rate limit detected. Auto-switched to fallback profile."}
EOF

exit 0
