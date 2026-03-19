#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
harness_start_timer 2>/dev/null || true

# ConfigChange hook (matcher: project_settings|local_settings, async) -- monitor config changes
# Performance target: < 10ms

# Early exit if debug mode is not enabled
[[ "${HARNESS_DEBUG:-}" == "1" ]] || { cat >/dev/null; harness_log "config-changed" "skip"; exit 0; }

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Extract fields
SOURCE=$(echo "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null) || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // "unknown"' 2>/dev/null) || exit 0

# Append to debug log
LOG_DIR="${HOME}/.claude"
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
echo "[$(date -Iseconds)] ConfigChange: source=$SOURCE file=$FILE_PATH" \
  >> "${LOG_DIR}/harness-debug.log" 2>/dev/null || true

harness_log "config-changed" "logged"
exit 0
