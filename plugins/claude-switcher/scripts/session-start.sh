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

# Verify active profile matches live credentials
live_email=""
if [ -f "${HOME}/.claude.json" ]; then
    live_email=$(jq -r '.oauthAccount.emailAddress // empty' "${HOME}/.claude.json" 2>/dev/null)
fi

if [ -n "$live_email" ] && [ -d "${PROFILES_DIR}/${active}" ]; then
    saved_email=$(jq -r '.emailAddress // empty' "${PROFILES_DIR}/${active}/account-metadata.json" 2>/dev/null)
    if [ -n "$saved_email" ] && [ "$live_email" != "$saved_email" ]; then
        # Live credentials don't match active profile -- find the right one
        matched=""
        for pdir in "$PROFILES_DIR"/*/; do
            [ -d "$pdir" ] || continue
            pname=$(basename "$pdir")
            pemail=$(jq -r '.emailAddress // empty' "${pdir}/account-metadata.json" 2>/dev/null)
            if [ "$pemail" = "$live_email" ]; then
                matched="$pname"
                break
            fi
        done
        if [ -n "$matched" ]; then
            # Auto-correct: update config to reflect actual credentials
            tmp=$(mktemp "${CONFIG_FILE}.XXXXXX")
            jq --arg p "$matched" --arg prev "$active" \
                '.active_profile = $p | .previous_profile = $prev' "$CONFIG_FILE" > "$tmp" \
                && mv "$tmp" "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
            active="$matched"
        else
            # Live credentials don't match any saved profile -- show live info directly
            live_org=$(jq -r '.oauthAccount.organizationName // empty' "${HOME}/.claude.json" 2>/dev/null)
            live_sub="unknown"
            if [ -f "${HOME}/.claude/.credentials.json" ]; then
                live_sub=$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' "${HOME}/.claude/.credentials.json" 2>/dev/null)
            fi
            cat <<EOF
{"result":"Claude Code profile: (unsaved) (${live_email}${live_org:+, $live_org}, ${live_sub}) -- use /save <name> to save this account"}
EOF
            exit 0
        fi
    fi
fi

# Auto-switch-back check
auto_switch_msg=""

if [ -f "$AUTO_SWITCH_CONFIG" ] && [ -f "$AUTO_SWITCH_STATE" ]; then
    enabled=$(jq -r '.enabled // false' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
    on_fb=$(jq -r '.on_fallback // false' "$AUTO_SWITCH_STATE" 2>/dev/null)

    if [ "$enabled" = "true" ] && [ "$on_fb" = "true" ]; then
        switch_back_at=$(jq -r '.switch_back_at // empty' "$AUTO_SWITCH_STATE" 2>/dev/null)
        original=$(jq -r '.original_profile // empty' "$AUTO_SWITCH_STATE" 2>/dev/null)

        should_switch_back=false

        if [ -n "$switch_back_at" ] && [ "$switch_back_at" != "null" ]; then
            now_epoch=$(date +%s)
            if [ "$now_epoch" -ge "$switch_back_at" ] 2>/dev/null; then
                should_switch_back=true
            fi
        fi

        if [ "$should_switch_back" = "true" ] && [ -n "$original" ]; then
            sh "$CLI" use "$original" >/dev/null 2>&1 || true
            sh "$CLI" auto-config reset-state >/dev/null 2>&1 || true

            active="$original"
            auto_switch_msg=" (auto-switched back from fallback -- limit reset)"
        else
            reason=$(jq -r '.reason // empty' "$AUTO_SWITCH_STATE" 2>/dev/null)
            # Format switch_back_at as human-readable
            switch_back_display=""
            if [ -n "$switch_back_at" ] && [ "$switch_back_at" != "null" ]; then
                switch_back_display=$(date -d "@$switch_back_at" "+%H:%M %Z" 2>/dev/null || date -r "$switch_back_at" "+%H:%M %Z" 2>/dev/null || echo "$switch_back_at")
            fi
            auto_switch_msg=" (on fallback due to ${reason}, primary: ${original}, switches back: ${switch_back_display:-unknown})"
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
        five_hour_pct=$(jq -r '.five_hour.used_percentage // 0' "$RATE_LIMITS_FILE" 2>/dev/null)
        seven_day_pct=$(jq -r '.seven_day.used_percentage // 0' "$RATE_LIMITS_FILE" 2>/dev/null)
        threshold=$(jq -r '.preemptive_switch_percent // 97' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
        usage_msg=" [5h: ${five_hour_pct}%, 7d: ${seven_day_pct}%, switches at ${threshold}%]"
    fi
fi

cat <<EOF
{"result":"Claude Code profile: ${active} (${email}${org:+, $org}, ${sub})${usage_msg}${auto_switch_msg}"}
EOF

exit 0
