#!/bin/sh
set -eu

# SessionStart hook: shows active profile and handles time-based auto-switch-back.

SWITCHER_DIR="${HOME}/.claude-switcher"
CONFIG_FILE="${SWITCHER_DIR}/config.json"
PROFILES_DIR="${SWITCHER_DIR}/profiles"
AUTO_SWITCH_CONFIG="${SWITCHER_DIR}/auto-switch.json"
AUTO_SWITCH_STATE="${SWITCHER_DIR}/auto-switch-state.json"
RATE_LIMITS_FILE="${SWITCHER_DIR}/rate-limits.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="${SCRIPT_DIR}/claude-switcher.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

active=$(jq -r '.active_profile // empty' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$active" ]; then
    exit 0
fi

# Auto-switch-back check
auto_switch_msg=""

if [ -f "$AUTO_SWITCH_CONFIG" ] && [ -f "$AUTO_SWITCH_STATE" ]; then
    enabled=$(jq -r '.enabled // false' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
    on_fb=$(jq -r '.on_fallback // false' "$AUTO_SWITCH_STATE" 2>/dev/null)

    if [ "$enabled" = "true" ] && [ "$on_fb" = "true" ]; then
        next_reset=$(jq -r '.next_reset // empty' "$AUTO_SWITCH_STATE" 2>/dev/null)
        original=$(jq -r '.original_profile // empty' "$AUTO_SWITCH_STATE" 2>/dev/null)

        should_switch_back=false

        if [ -n "$next_reset" ]; then
            now_epoch=$(date +%s)
            reset_epoch=$(date -d "$next_reset" "+%s" 2>/dev/null || echo "")

            if [ -z "$reset_epoch" ]; then
                case "$next_reset" in
                    [0-9]*) reset_epoch="$next_reset" ;;
                esac
            fi

            if [ -n "$reset_epoch" ] && [ "$now_epoch" -ge "$reset_epoch" ]; then
                should_switch_back=true
            fi
        fi

        if [ "$should_switch_back" = "true" ] && [ -n "$original" ]; then
            sh "$CLI" use "$original" >/dev/null 2>&1 || true

            cat > "$AUTO_SWITCH_STATE" <<JSON
{
  "on_fallback": false,
  "original_profile": null,
  "fallback_profile": null,
  "switched_at": $(date +%s),
  "reason": null,
  "next_reset": null
}
JSON
            chmod 600 "$AUTO_SWITCH_STATE"

            # Clear auto-switch state since we're back on primary
            sh "$CLI" auto-config reset-state >/dev/null 2>&1 || true

            active="$original"
            auto_switch_msg=" (auto-switched back from fallback -- limit reset)"
        else
            reason=$(jq -r '.reason // empty' "$AUTO_SWITCH_STATE" 2>/dev/null)
            auto_switch_msg=" (on fallback due to ${reason}, primary: ${original}, resets: ${next_reset:-unknown})"
        fi
    fi
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
        five_hour_pct=$(jq -r '.five_hour.percent // 0' "$RATE_LIMITS_FILE" 2>/dev/null)
        seven_day_pct=$(jq -r '.seven_day.percent // 0' "$RATE_LIMITS_FILE" 2>/dev/null)
        threshold=$(jq -r '.preemptive_switch_percent // 97' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
        usage_msg=" [5h: ${five_hour_pct}%, 7d: ${seven_day_pct}%, switches at ${threshold}%]"
    fi
fi

cat <<EOF
{"result":"Claude Code profile: ${active} (${email}${org:+, $org}, ${sub})${usage_msg}${auto_switch_msg}"}
EOF

exit 0
