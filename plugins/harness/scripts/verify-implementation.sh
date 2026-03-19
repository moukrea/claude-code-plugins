#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
harness_start_timer || true

# SubagentStop hook (matcher: implementer) -- verify implementer work is complete
# Performance target: < 100ms

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Extract last assistant message
MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null) || exit 0
[[ -n "$MESSAGE" ]] || exit 0

# Check for indicators of incomplete work (case-insensitive)
MESSAGE_LOWER=$(echo "$MESSAGE" | tr '[:upper:]' '[:lower:]')

INCOMPLETE_PATTERNS=(
  "todo"
  "not yet implemented"
  "will do later"
  "placeholder"
  "stub"
  "not implemented"
  "left as an exercise"
  "will be implemented"
  "needs to be done"
  "haven't implemented"
  "skip for now"
)

for pattern in "${INCOMPLETE_PATTERNS[@]}"; do
  if echo "$MESSAGE_LOWER" | grep -qF "$pattern" 2>/dev/null; then
    harness_log "verify-implementation" "block" "found marker: $pattern"
    echo "Implementation appears incomplete. Please finish all TODO items before stopping." >&2
    exit 2
  fi
done

harness_log "verify-implementation" "pass"
exit 0
