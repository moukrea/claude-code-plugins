# shellcheck shell=bash
# Auto-switch state and configuration management for claude-switcher
# Sourced by the main entry point -- not executed directly

init_auto_switch_config() {
    if [ ! -f "$AUTO_SWITCH_CONFIG" ]; then
        cat > "$AUTO_SWITCH_CONFIG" <<'JSON'
{
  "enabled": false,
  "primary_profile": null,
  "fallback_profiles": [],
  "preemptive_switch_percent": 97
}
JSON
        chmod 600 "$AUTO_SWITCH_CONFIG"
    else
        # Migrate: remove deprecated fields from older configs
        local needs_update=false
        if ! jq -e '.preemptive_switch_percent' "$AUTO_SWITCH_CONFIG" >/dev/null 2>&1; then
            needs_update=true
        fi
        if jq -e '.estimated_daily_capacity' "$AUTO_SWITCH_CONFIG" >/dev/null 2>&1; then
            needs_update=true
        fi
        if jq -e '.daily_reset_time' "$AUTO_SWITCH_CONFIG" >/dev/null 2>&1; then
            needs_update=true
        fi
        if [ "$needs_update" = true ]; then
            local tmp
            tmp=$(mktemp "${AUTO_SWITCH_CONFIG}.XXXXXX")
            jq '. + {preemptive_switch_percent: (.preemptive_switch_percent // 97)}
                | del(.estimated_daily_capacity, .daily_reset_time, .daily_reset_timezone, .weekly_reset_day, .weekly_reset_time)' \
                "$AUTO_SWITCH_CONFIG" > "$tmp" && mv "$tmp" "$AUTO_SWITCH_CONFIG"
            chmod 600 "$AUTO_SWITCH_CONFIG"
        fi
    fi
}

get_auto_config_value() {
    jq -r ".$1 // empty" "$AUTO_SWITCH_CONFIG" 2>/dev/null
}

set_auto_config_value() {
    local key="$1" value="$2"
    local tmp
    tmp=$(mktemp "${AUTO_SWITCH_CONFIG}.XXXXXX")
    if [ "$value" = "true" ] || [ "$value" = "false" ] || [ "$value" = "null" ]; then
        jq ".$key = $value" "$AUTO_SWITCH_CONFIG" > "$tmp" && mv "$tmp" "$AUTO_SWITCH_CONFIG"
    elif [ "${value#\[}" != "$value" ]; then
        # Starts with [ -- JSON array
        jq --argjson v "$value" ".$key = \$v" "$AUTO_SWITCH_CONFIG" > "$tmp" && mv "$tmp" "$AUTO_SWITCH_CONFIG"
    elif echo "$value" | grep -qE '^[0-9]+$'; then
        # Pure integer
        jq --argjson v "$value" ".$key = \$v" "$AUTO_SWITCH_CONFIG" > "$tmp" && mv "$tmp" "$AUTO_SWITCH_CONFIG"
    else
        jq --arg v "$value" ".$key = \$v" "$AUTO_SWITCH_CONFIG" > "$tmp" && mv "$tmp" "$AUTO_SWITCH_CONFIG"
    fi
    chmod 600 "$AUTO_SWITCH_CONFIG"
}

get_auto_switch_state() {
    if [ -f "$AUTO_SWITCH_STATE" ]; then
        jq -r ".$1 // empty" "$AUTO_SWITCH_STATE" 2>/dev/null
    fi
}

set_auto_switch_state() {
    local on_fallback="$1" original="$2" fallback="$3" reason="$4"
    local five_resets="${5:-}" seven_resets="${6:-}" switch_back="${7:-}"
    local now
    now=$(date +%s)
    cat > "$AUTO_SWITCH_STATE" <<EOF
{
  "on_fallback": $on_fallback,
  "original_profile": $([ -n "$original" ] && echo "\"$original\"" || echo "null"),
  "fallback_profile": $([ -n "$fallback" ] && echo "\"$fallback\"" || echo "null"),
  "switched_at": $now,
  "reason": $([ -n "$reason" ] && echo "\"$reason\"" || echo "null"),
  "primary_resets_at": {
    "five_hour": $([ -n "$five_resets" ] && echo "$five_resets" || echo "null"),
    "seven_day": $([ -n "$seven_resets" ] && echo "$seven_resets" || echo "null")
  },
  "switch_back_at": $([ -n "$switch_back" ] && echo "$switch_back" || echo "null")
}
EOF
    chmod 600 "$AUTO_SWITCH_STATE"
}

clear_auto_switch_state() {
    set_auto_switch_state "false" "" "" "" "" "" ""
}

is_past_reset_time() {
    local switch_back_at
    switch_back_at=$(get_auto_switch_state "switch_back_at")
    [ -z "$switch_back_at" ] || [ "$switch_back_at" = "null" ] && return 1

    local now_epoch
    now_epoch=$(date +%s)
    [ "$now_epoch" -ge "$switch_back_at" ] 2>/dev/null
}

get_next_fallback() {
    local current_profile="$1"
    local fallbacks
    fallbacks=$(jq -r '.fallback_profiles[]' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
    [ -z "$fallbacks" ] && return 1

    local result=""
    while IFS= read -r fb; do
        if [ "$fb" != "$current_profile" ] && profile_exists "$fb"; then
            result="$fb"
            break
        fi
    done <<EOF
$fallbacks
EOF

    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi
    return 1
}

do_auto_switch_to_fallback() {
    local reason="${1:-rate_limit}"
    local five_resets="${2:-}" seven_resets="${3:-}" switch_back_at="${4:-}"
    local current
    current=$(get_config_value "active_profile")
    local primary
    primary=$(get_auto_config_value "primary_profile")

    # Save current rate limits to primary profile before switching
    save_rate_limits_for_active_profile

    local fallback
    fallback=$(get_next_fallback "$current") || {
        echo "error: no fallback profile available." >&2
        return 1
    }

    set_auto_switch_state "true" "${primary:-$current}" "$fallback" "$reason" "$five_resets" "$seven_resets" "$switch_back_at"
    cmd_use "$fallback"
}

do_auto_switch_back() {
    local original
    original=$(get_auto_switch_state "original_profile")
    [ -z "$original" ] && return 1

    if ! profile_exists "$original"; then
        echo "error: original profile '$original' no longer exists." >&2
        return 1
    fi

    cmd_use "$original" && clear_auto_switch_state
}
