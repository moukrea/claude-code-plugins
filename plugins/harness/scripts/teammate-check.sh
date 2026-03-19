#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
harness_start_timer 2>/dev/null || true

# TeammateIdle hook (blocking) -- ensure teammates pick up remaining work
# Performance target: < 5s

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Extract teammate name
TEAMMATE=$(echo "$INPUT" | jq -r '.teammate_name // empty' 2>/dev/null) || exit 0

# Instead of spawning a recursive claude session (expensive and potentially recursive),
# inject a reminder to the lead agent and allow the idle transition.
harness_log "teammate-check" "pass" "injecting idle reminder for $TEAMMATE"
jq -nc --arg name "$TEAMMATE" '{"additionalContext": ("Teammate " + $name + " going idle. Check if there are unclaimed tasks in the task list that should be assigned.")}'
exit 0
