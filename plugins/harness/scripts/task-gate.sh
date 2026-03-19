#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
source "$(dirname "$0")/lib/detect.sh" 2>/dev/null || true
harness_start_timer 2>/dev/null || true

# TaskCompleted hook (blocking) -- verify task completion claim is valid
# Performance target: < 30s

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Extract task info (for logging/context, not strictly needed for verification)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // empty' 2>/dev/null) || true

# Detect verification command
TEST_CMD=$(detect_test_cmd)

# If no test command found, allow completion
[[ -n "$TEST_CMD" ]] || { harness_log "task-gate" "skip"; exit 0; }

# Run tests with timeout
OUTPUT=$(timeout 30 bash -c "$TEST_CMD" 2>&1) || {
  EXIT_CODE=$?
  if [[ "$EXIT_CODE" -eq 124 ]]; then
    echo "Cannot mark task complete: test verification timed out after 30s running: $TEST_CMD" >&2
    harness_log "task-gate" "block" "timeout after 30s"
    exit 2
  fi
  TRUNCATED=$(echo "$OUTPUT" | head -c 500)
  echo "Cannot mark task complete: tests are failing. Output: $TRUNCATED" >&2
  harness_log "task-gate" "block" "$TRUNCATED"
  exit 2
}

# Tests passed
harness_log "task-gate" "pass"
exit 0
