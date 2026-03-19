#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
harness_start_timer 2>/dev/null || true

# Notification hook (matcher: idle_prompt, async) -- desktop notification
# Performance target: < 200ms

# Read stdin (consume it)
INPUT=$(cat) || exit 0

# Detect OS and send notification
_NOTIFY_PLATFORM=""
case "$(uname -s)" in
  Darwin)
    osascript -e 'display notification "Claude is ready" with title "Harness"' 2>/dev/null || true
    _NOTIFY_PLATFORM="macOS"
    ;;
  Linux)
    if command -v notify-send >/dev/null 2>&1; then
      notify-send 'Harness' 'Claude is ready for your next instruction' 2>/dev/null || true
    fi
    _NOTIFY_PLATFORM="Linux"
    ;;
esac

harness_log "notify" "sent" "$_NOTIFY_PLATFORM"
exit 0
