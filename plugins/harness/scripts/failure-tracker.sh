#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
harness_start_timer || true

# PostToolUseFailure hook (matcher: Bash, async) -- track failure patterns
# Performance target: < 50ms

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Extract error and command
ERROR=$(echo "$INPUT" | jq -r '.error // empty' 2>/dev/null) || exit 0
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0

[[ -n "$ERROR" ]] || exit 0

SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
LOG_FILE="/tmp/harness-failures-${SESSION_ID}.log"

# Create a simple error signature for pattern matching (first line, key words)
ERROR_SIG=$(echo "$ERROR" | head -1 | sed 's/[0-9]//g' | tr -s ' ' | cut -c1-80)

# Log rotation: if log exceeds 100 lines, truncate to last 50
if [[ -f "$LOG_FILE" ]]; then
  LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null) || LINE_COUNT=0
  if [[ "$LINE_COUNT" -gt 100 ]]; then
    tail -50 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null || true
  fi
fi

# Append failure record
echo "$(date +%s)|$ERROR_SIG|$COMMAND" >> "$LOG_FILE" 2>/dev/null || exit 0

# Count consecutive similar failures (last N lines with same signature)
SIMILAR_COUNT=0
if [[ -f "$LOG_FILE" ]]; then
  SIMILAR_COUNT=$(tail -10 "$LOG_FILE" | grep -cF "$ERROR_SIG" 2>/dev/null) || true
fi

if [[ "$SIMILAR_COUNT" -ge 3 ]]; then
  harness_log "failure-tracker" "warn" "3+ similar failures: $ERROR_SIG"
  jq -nc '{"additionalContext": "[HARNESS] The same type of error has occurred 3+ times. Consider: (1) checking if the command/tool is installed, (2) reviewing the approach, (3) using /recovery skill."}'
else
  harness_log "failure-tracker" "track" "count=$SIMILAR_COUNT sig=$ERROR_SIG"
fi

exit 0
