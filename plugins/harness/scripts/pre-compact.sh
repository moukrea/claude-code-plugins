#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
harness_start_timer 2>/dev/null || true

# PreCompact hook (matcher: auto) -- preserve critical state before compaction
# Performance target: < 100ms

# Read stdin (consume it even if unused)
INPUT=$(cat) || exit 0

# Require jq for output
command -v jq >/dev/null 2>&1 || exit 0

SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
STATE_FILE="/tmp/harness-precompact-${SESSION_ID}.json"

# Collect git state
BRANCH=""
COMMITS="[]"
MODIFIED=0

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
  COMMITS=$(git log --oneline -5 --format='%H' 2>/dev/null | jq -Rn '[inputs]' 2>/dev/null || echo '[]')
  MODIFIED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
fi

# Write state file
jq -nc \
  --arg branch "$BRANCH" \
  --argjson commits "$COMMITS" \
  --argjson modified "$MODIFIED" \
  --argjson ts "$(date +%s)" \
  '{branch: $branch, commits: $commits, modified_count: $modified, timestamp: $ts}' \
  > "$STATE_FILE" 2>/dev/null || true

harness_log "pre-compact" "saved" "$BRANCH"
exit 0
