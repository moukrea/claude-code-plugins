#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
harness_start_timer 2>/dev/null || true

# PostCompact hook (async) -- inject context if state changed during compaction
# Performance target: < 100ms

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
STATE_FILE="/tmp/harness-precompact-${SESSION_ID}.json"

# If no pre-compact state was saved, nothing to compare
[[ -f "$STATE_FILE" ]] || exit 0

# Read saved state
SAVED_BRANCH=$(jq -r '.branch // empty' "$STATE_FILE" 2>/dev/null) || exit 0
SAVED_COMMITS=$(jq -r '.commits[0] // empty' "$STATE_FILE" 2>/dev/null) || exit 0
SAVED_MODIFIED=$(jq -r '.modified_count // 0' "$STATE_FILE" 2>/dev/null) || exit 0

# Get current state
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "")
CURRENT_MODIFIED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# Compare states
changes=()

if [[ "$CURRENT_BRANCH" != "$SAVED_BRANCH" && -n "$SAVED_BRANCH" ]]; then
  changes+=("Branch changed: $SAVED_BRANCH -> $CURRENT_BRANCH.")
fi

if [[ -n "$CURRENT_HEAD" && -n "$SAVED_COMMITS" && "$CURRENT_HEAD" != "$SAVED_COMMITS" ]]; then
  NEW_COMMITS=$(git rev-list "${SAVED_COMMITS}..HEAD" --count 2>/dev/null) || NEW_COMMITS=0
  if [[ "$NEW_COMMITS" -gt 0 ]]; then
    changes+=("$NEW_COMMITS new commit(s) since compaction.")
  fi
fi

if [[ "$CURRENT_MODIFIED" != "$SAVED_MODIFIED" ]]; then
  changes+=("Uncommitted files: $SAVED_MODIFIED -> $CURRENT_MODIFIED.")
fi

# Clean up state file
rm -f "$STATE_FILE" 2>/dev/null || true

# Output only if something changed
if [[ ${#changes[@]} -gt 0 ]]; then
  CONTEXT="[HARNESS] State changed during compaction: $(IFS=' '; echo "${changes[*]}")"
  jq -nc --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
  harness_log "post-compact" "inject"
else
  harness_log "post-compact" "silent"
fi

exit 0
