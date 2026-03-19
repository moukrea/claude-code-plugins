#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
source "$(dirname "$0")/lib/detect.sh" 2>/dev/null || true
harness_start_timer || true

# Stop hook (blocking) -- prevent stopping with failing tests
# Performance target: < 30s (includes running tests)

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Check stop_hook_active to prevent infinite loops
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
if [[ "$STOP_ACTIVE" == "true" ]]; then
  harness_log "stop-gate" "loop-prevention"
  exit 0
fi

# detect_test_cmd and detect_lint_cmd provided by lib/detect.sh
TEST_CMD=$(detect_test_cmd)
LINT_CMD=$(detect_lint_cmd 2>/dev/null) || LINT_CMD=""

# If no verification command found, don't block
if [[ -z "$TEST_CMD" && -z "$LINT_CMD" ]]; then
  harness_log "stop-gate" "skip" "no verification command found"
  exit 0
fi

BLOCK_MSG=""

# Run tests with timeout (if test command exists)
if [[ -n "$TEST_CMD" ]]; then
  TEST_OUTPUT=$(timeout 30 bash -c "$TEST_CMD" 2>&1) || {
    EXIT_CODE=$?
    if [[ "$EXIT_CODE" -eq 124 ]]; then
      harness_log "stop-gate" "block" "verification timed out"
      echo "Verification timed out after 30s running: $TEST_CMD" >&2
      exit 2
    fi
    TRUNCATED=$(echo "$TEST_OUTPUT" | head -c 500)
    BLOCK_MSG="Tests failing. Output of \`$TEST_CMD\`:"$'\n'"$TRUNCATED"
  }
fi

# Run lint with timeout (if lint command exists)
if [[ -n "$LINT_CMD" ]]; then
  LINT_OUTPUT=$(timeout 30 bash -c "$LINT_CMD" 2>&1) || {
    EXIT_CODE=$?
    if [[ "$EXIT_CODE" -eq 124 ]]; then
      harness_log "stop-gate" "block" "lint timed out"
      echo "Lint timed out after 30s running: $LINT_CMD" >&2
      exit 2
    fi
    LINT_TRUNCATED=$(echo "$LINT_OUTPUT" | head -c 500)
    if [[ -n "$BLOCK_MSG" ]]; then
      BLOCK_MSG="${BLOCK_MSG}"$'\n\n'"Lint failing. Output of \`$LINT_CMD\`:"$'\n'"$LINT_TRUNCATED"
    else
      BLOCK_MSG="Lint failing. Output of \`$LINT_CMD\`:"$'\n'"$LINT_TRUNCATED"
    fi
  }
fi

# Block if any failures
if [[ -n "$BLOCK_MSG" ]]; then
  FIRST_LINE=$(echo "$BLOCK_MSG" | head -1)
  harness_log "stop-gate" "block" "$FIRST_LINE"
  echo "Cannot stop. $BLOCK_MSG" >&2
  exit 2
fi

# All checks passed
harness_log "stop-gate" "pass"
exit 0
