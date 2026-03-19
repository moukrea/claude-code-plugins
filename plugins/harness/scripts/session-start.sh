#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
source "$(dirname "$0")/lib/detect.sh" 2>/dev/null || true
harness_start_timer || true

# SessionStart hook (matcher: startup) -- detect project environment
# Performance target: < 200ms

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Parse source field; exit silently if not startup or bad JSON
SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null) || exit 0
if [[ "$SOURCE" != "startup" ]]; then
  harness_log "session-start" "skip" "source=$SOURCE"
  exit 0
fi

context_parts=()

# --- Detect project type and verification commands ---
PROJECT_TYPE=$(detect_project_type)
TEST_CMD=$(detect_test_cmd)
LINT_CMD=$(detect_lint_cmd)
BUILD_CMD=$(detect_build_cmd)

if [[ -n "$PROJECT_TYPE" ]]; then
  part="Project: $PROJECT_TYPE."
  if [[ -n "$TEST_CMD" ]]; then part="$part Test: \`$TEST_CMD\`."; fi
  if [[ -n "$LINT_CMD" ]]; then part="$part Lint: \`$LINT_CMD\`."; fi
  if [[ -n "$BUILD_CMD" ]]; then part="$part Build: \`$BUILD_CMD\`."; fi
  context_parts+=("$part")
fi

# --- Git status ---
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
  CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  git_part="Branch: $BRANCH"
  if [[ "$CHANGES" -gt 0 ]]; then git_part="$git_part (+$CHANGES uncommitted)"; fi
  context_parts+=("$git_part.")
fi

# --- Task list ---
if [[ -n "${CLAUDE_CODE_TASK_LIST_ID:-}" ]]; then
  context_parts+=("Tasks may be available via Ctrl+T.")
fi

# Output only if we have something useful
if [[ ${#context_parts[@]} -eq 0 ]]; then
  harness_log "session-start" "silent"
  exit 0
fi

CONTEXT=$(IFS=' '; echo "${context_parts[*]}")
harness_log "session-start" "inject" "detected: ${PROJECT_TYPE:-unknown}"
jq -nc --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
