#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
harness_start_timer || true

# UserPromptSubmit hook -- fast heuristic classification of prompt complexity
# Performance target: < 200ms

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Extract user prompt; exit silently on missing/bad JSON
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
[[ -n "$PROMPT" ]] || exit 0

# Word count
WORD_COUNT=$(echo "$PROMPT" | wc -w | tr -d ' ')

# Check for indicators (case-insensitive)
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

has_pattern() {
  echo "$PROMPT_LOWER" | grep -qE "$1" 2>/dev/null
}

# File references count (paths like src/foo.ts, ./bar.py, etc.)
FILE_REFS=$(echo "$PROMPT" | grep -oE '[a-zA-Z0-9_./-]*\/[a-zA-Z0-9_./-]+\.[a-zA-Z]{1,6}' 2>/dev/null | wc -l | tr -d ' ') || FILE_REFS=0

# Classify complexity
COMPLEXITY="simple"
EFFORT="low"
NEEDS_INTERVIEW=false

if [[ "$WORD_COUNT" -gt 500 ]] || has_pattern '(requirements|specification|prd|acceptance criteria)'; then
  COMPLEXITY="massive"
  EFFORT="max"
elif [[ "$WORD_COUNT" -gt 150 ]] || { [[ "$FILE_REFS" -gt 5 ]] && has_pattern '(migration|cross-cutting|refactor.*all|across)'; }; then
  COMPLEXITY="complex"
  EFFORT="high"
elif [[ "$WORD_COUNT" -gt 50 ]] || { [[ "$WORD_COUNT" -gt 15 ]] && has_pattern '(add.*feature|new feature|refactor|implement|create.*new|build.*new|design.*system|migrate|redesign)'; }; then
  COMPLEXITY="medium"
  EFFORT="medium"
else
  # Simple: short prompts about fixes, typos, small changes
  COMPLEXITY="simple"
  EFFORT="low"
fi

# Vague prompt detection for interview recommendation
if [[ "$COMPLEXITY" != "simple" ]]; then
  if has_pattern '(make it better|improve|something|somehow|not sure|maybe)' || \
     { [[ "$WORD_COUNT" -lt 15 ]] && [[ "$COMPLEXITY" != "simple" ]]; }; then
    NEEDS_INTERVIEW=true
  fi
fi

# Build recommendation
RECOMMEND=""
case "$COMPLEXITY" in
  simple)  RECOMMEND="Proceed directly with implementation and verify." ;;
  medium)  RECOMMEND="Consider: explore the codebase first, then plan, then implement with verification." ;;
  complex) RECOMMEND="Consider: decompose into tasks, use subagents for parallel work, verify each piece." ;;
  massive) RECOMMEND="Consider: ingest spec fully, decompose into granular tasks, use agent teams or batch processing." ;;
esac

if [[ "$NEEDS_INTERVIEW" == "true" ]]; then
  RECOMMEND="The prompt is vague for this complexity level -- clarify requirements first. $RECOMMEND"
fi

# Simple tasks: no context injection (zero overhead)
if [[ "$COMPLEXITY" == "simple" ]]; then
  harness_log "classify-prompt" "simple"
  exit 0
fi

CONTEXT="[HARNESS] Task classified as $COMPLEXITY. Recommended effort: $EFFORT. $RECOMMEND"

harness_log "classify-prompt" "$COMPLEXITY"
jq -nc --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
