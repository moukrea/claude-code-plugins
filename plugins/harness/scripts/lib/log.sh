#!/usr/bin/env bash
# Shared logging helper for harness hooks
# Source this at the top of each hook script:
#   source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
#
# Usage:
#   harness_start_timer              # call once at script start
#   harness_log <hook> <decision> [detail]   # call before each exit
#
# Writes JSONL to .harness/logs/harness.log
# ALL failures are silent -- logging must never break hooks

_HARNESS_LOG_DIR="${HARNESS_LOG_DIR:-.harness/logs}"
_HARNESS_LOG_FILE="${_HARNESS_LOG_DIR}/harness.log"
_HARNESS_START_MS=""

harness_start_timer() {
  _HARNESS_START_MS=$(date +%s%3N 2>/dev/null) || _HARNESS_START_MS=""
  # On macOS, %3N becomes literal "3N" -- detect and fallback
  [[ "${_HARNESS_START_MS:-}" == *N* ]] && _HARNESS_START_MS="$(date +%s)000"
  return 0
}

harness_log() {
  {
    local hook="${1:-unknown}" decision="${2:-ok}" detail="${3:-}"
    local ts duration_ms=""

    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || ts="unknown"

    if [[ -n "$_HARNESS_START_MS" ]]; then
      local end_ms
      end_ms=$(date +%s%3N 2>/dev/null) || end_ms=""
      [[ "${end_ms:-}" == *N* ]] && end_ms="$(date +%s)000"
      [[ -n "$end_ms" ]] && duration_ms=$(( end_ms - _HARNESS_START_MS ))
    fi

    mkdir -p "$_HARNESS_LOG_DIR" 2>/dev/null || return 0

    if command -v jq >/dev/null 2>&1; then
      jq -nc \
        --arg ts "$ts" \
        --arg hook "$hook" \
        --arg decision "$decision" \
        --arg detail "$detail" \
        --argjson dur "${duration_ms:-null}" \
        '{timestamp:$ts, hook:$hook, decision:$decision}
         + (if $detail != "" then {detail:$detail} else {} end)
         + (if $dur then {duration_ms:$dur} else {} end)' \
        >> "$_HARNESS_LOG_FILE" 2>/dev/null
    else
      # Fallback without jq
      local line="{\"timestamp\":\"${ts}\",\"hook\":\"${hook}\",\"decision\":\"${decision}\""
      [[ -n "$detail" ]] && line="${line},\"detail\":$(printf '%s' "$detail" | sed 's/\\/\\\\/g;s/"/\\"/g;s/\t/\\t/g' | sed 's/.*/"&"/')"
      [[ -n "$duration_ms" ]] && line="${line},\"duration_ms\":${duration_ms}"
      echo "${line}}" >> "$_HARNESS_LOG_FILE" 2>/dev/null
    fi
  } 2>/dev/null || true
}
