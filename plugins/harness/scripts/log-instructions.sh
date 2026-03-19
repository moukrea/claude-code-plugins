#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
harness_start_timer 2>/dev/null || true

# InstructionsLoaded hook (async) -- debug logging for rule/instruction loading
# Performance target: < 10ms

# Early exit if debug mode is not enabled
[[ "${HARNESS_DEBUG:-}" == "1" ]] || { cat >/dev/null; harness_log "log-instructions" "skip"; exit 0; }

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Extract fields
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // "unknown"' 2>/dev/null) || exit 0
MEMORY_TYPE=$(echo "$INPUT" | jq -r '.memory_type // "unknown"' 2>/dev/null) || exit 0
LOAD_REASON=$(echo "$INPUT" | jq -r '.load_reason // "unknown"' 2>/dev/null) || exit 0

# Append to debug log
LOG_DIR="${HOME}/.claude"
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
echo "[$(date -Iseconds)] InstructionsLoaded: file=$FILE_PATH type=$MEMORY_TYPE reason=$LOAD_REASON" \
  >> "${LOG_DIR}/harness-debug.log" 2>/dev/null || true

harness_log "log-instructions" "logged"
exit 0
