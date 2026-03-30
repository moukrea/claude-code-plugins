#!/bin/sh
set -eu

# SessionStart hook: shows active profile info.
# Auto-switch logic (mismatch detection, switch-back) is handled by
# the status line helper (statusline-autoswitch.sh) which runs continuously.

SWITCHER_DIR="${HOME}/.claude-switcher"
CONFIG_FILE="${SWITCHER_DIR}/config.json"
PROFILES_DIR="${SWITCHER_DIR}/profiles"
AUTO_SWITCH_CONFIG="${SWITCHER_DIR}/auto-switch.json"
AUTO_SWITCH_STATE="${SWITCHER_DIR}/auto-switch-state.json"
RATE_LIMITS_FILE="${SWITCHER_DIR}/rate-limits.json"

if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

active=$(jq -r '.active_profile // empty' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$active" ]; then
    exit 0
fi

# Build profile info
meta_file="${PROFILES_DIR}/${active}/account-metadata.json"
creds_file="${PROFILES_DIR}/${active}/credentials.json"

if [ ! -f "$meta_file" ]; then
    exit 0
fi

email=$(jq -r '.emailAddress // "unknown"' "$meta_file" 2>/dev/null)
org=$(jq -r '.organizationName // empty' "$meta_file" 2>/dev/null)
sub=$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' "$creds_file" 2>/dev/null)

# Rate limit info
usage_msg=""
if [ -f "$AUTO_SWITCH_CONFIG" ] && [ -f "$RATE_LIMITS_FILE" ]; then
    enabled_check=$(jq -r '.enabled // false' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
    if [ "$enabled_check" = "true" ]; then
        five_hour_pct=$(jq -r '.five_hour.used_percentage // 0' "$RATE_LIMITS_FILE" 2>/dev/null)
        seven_day_pct=$(jq -r '.seven_day.used_percentage // 0' "$RATE_LIMITS_FILE" 2>/dev/null)
        threshold=$(jq -r '.preemptive_switch_percent // 97' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
        usage_msg=" [5h: ${five_hour_pct}%, 7d: ${seven_day_pct}%, switches at ${threshold}%]"
    fi
fi

# Auto-switch status
auto_switch_msg=""
if [ -f "$AUTO_SWITCH_CONFIG" ] && [ -f "$AUTO_SWITCH_STATE" ]; then
    enabled=$(jq -r '.enabled // false' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
    on_fb=$(jq -r '.on_fallback // false' "$AUTO_SWITCH_STATE" 2>/dev/null)

    if [ "$enabled" = "true" ] && [ "$on_fb" = "true" ]; then
        reason=$(jq -r '.reason // empty' "$AUTO_SWITCH_STATE" 2>/dev/null)
        original=$(jq -r '.original_profile // empty' "$AUTO_SWITCH_STATE" 2>/dev/null)
        switch_back_at=$(jq -r '.switch_back_at // empty' "$AUTO_SWITCH_STATE" 2>/dev/null)

        switch_back_display=""
        if [ -n "$switch_back_at" ] && [ "$switch_back_at" != "null" ]; then
            switch_back_display=$(date -d "@$switch_back_at" "+%H:%M %Z" 2>/dev/null || date -r "$switch_back_at" "+%H:%M %Z" 2>/dev/null || echo "$switch_back_at")
        fi
        auto_switch_msg=" (on fallback due to ${reason}, primary: ${original}, switches back: ${switch_back_display:-unknown})"
    fi
fi

cat <<EOF
{"result":"Claude Code profile: ${active} (${email}${org:+, $org}, ${sub})${usage_msg}${auto_switch_msg}"}
EOF

exit 0
