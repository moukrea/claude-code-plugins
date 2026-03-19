#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
harness_start_timer || true

# PreToolUse hook (matcher: Write|Edit) -- prevent destructive writes to critical files
# Performance target: < 100ms

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Extract file path; exit silently on bad JSON
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -n "$FILE_PATH" ]] || exit 0

BASENAME=$(basename "$FILE_PATH")

# --- Lock file warning (non-blocking) ---
case "$BASENAME" in
  package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock)
    # Warn via additionalContext but do not block
    harness_log "guard-writes" "warn" "lock file: $BASENAME"
    jq -nc '{"additionalContext": "[HARNESS] Warning: editing a lock file directly. This is usually generated automatically."}'
    exit 0
    ;;
esac

# --- Test file protection ---
IS_TEST_FILE=false
case "$BASENAME" in
  *.test.*|*.spec.*|*_test.*|test_*.*|*_spec.*|*Test.*|*Tests.*) IS_TEST_FILE=true ;;
esac

# Also check path patterns
case "$FILE_PATH" in
  */__tests__/*|*/test/*|*/tests/*) IS_TEST_FILE=true ;;
esac

if [[ "$IS_TEST_FILE" == "true" ]]; then
  OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null) || true
  NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null) || true

  # Only check Edit tool (has old_string); Write tool full rewrites are harder to judge
  if [[ -n "$OLD_STRING" ]]; then
    OLD_LINES=$(echo "$OLD_STRING" | wc -l)
    NEW_LINES=$(echo "$NEW_STRING" | wc -l)

    # Check if old_string contains test constructs that new_string doesn't
    OLD_HAS_TESTS=false
    echo "$OLD_STRING" | grep -qE '(test\(|it\(|describe\(|def test_|fn test_|func Test|#\[test\])' 2>/dev/null && OLD_HAS_TESTS=true

    NEW_HAS_TESTS=false
    if [[ -n "$NEW_STRING" ]]; then
      echo "$NEW_STRING" | grep -qE '(test\(|it\(|describe\(|def test_|fn test_|func Test|#\[test\])' 2>/dev/null && NEW_HAS_TESTS=true
    fi

    # Block if old has tests and new doesn't (test removal)
    if [[ "$OLD_HAS_TESTS" == "true" && "$NEW_HAS_TESTS" == "false" ]]; then
      harness_log "guard-writes" "block" "test removal in $BASENAME"
      echo "Blocked: Cannot remove test cases. Tests must only be added or modified, never removed." >&2
      exit 2
    fi

    # Block if significant line reduction in test file with test constructs
    if [[ "$OLD_HAS_TESTS" == "true" && "$OLD_LINES" -gt 5 && "$NEW_LINES" -lt $(( OLD_LINES / 2 )) ]]; then
      harness_log "guard-writes" "block" "significant line reduction in $BASENAME"
      echo "Blocked: Cannot remove test cases. Tests must only be added or modified, never removed." >&2
      exit 2
    fi
  fi
fi

harness_log "guard-writes" "pass"
exit 0
