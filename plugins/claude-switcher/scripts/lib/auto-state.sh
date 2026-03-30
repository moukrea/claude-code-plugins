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
  "daily_reset_time": "15:00",
  "daily_reset_timezone": "Europe/Paris",
  "weekly_reset_day": "Monday",
  "weekly_reset_time": "10:00",
  "preemptive_switch_percent": 97
}
JSON
        chmod 600 "$AUTO_SWITCH_CONFIG"
    else
        local needs_update=false
        if ! jq -e '.preemptive_switch_percent' "$AUTO_SWITCH_CONFIG" >/dev/null 2>&1; then
            needs_update=true
        fi
        if jq -e '.estimated_daily_capacity' "$AUTO_SWITCH_CONFIG" >/dev/null 2>&1; then
            needs_update=true
        fi
        if [ "$needs_update" = true ]; then
            local tmp
            tmp=$(mktemp "${AUTO_SWITCH_CONFIG}.XXXXXX")
            jq '. + {preemptive_switch_percent: (.preemptive_switch_percent // 97)} | del(.estimated_daily_capacity)' "$AUTO_SWITCH_CONFIG" > "$tmp" && mv "$tmp" "$AUTO_SWITCH_CONFIG"
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
    local now
    now=$(date +%s)
    local next_reset
    next_reset=$(compute_next_reset)
    cat > "$AUTO_SWITCH_STATE" <<EOF
{
  "on_fallback": $on_fallback,
  "original_profile": $([ -n "$original" ] && echo "\"$original\"" || echo "null"),
  "fallback_profile": $([ -n "$fallback" ] && echo "\"$fallback\"" || echo "null"),
  "switched_at": $now,
  "reason": $([ -n "$reason" ] && echo "\"$reason\"" || echo "null"),
  "next_reset": $([ -n "$next_reset" ] && echo "\"$next_reset\"" || echo "null")
}
EOF
    chmod 600 "$AUTO_SWITCH_STATE"
}

clear_auto_switch_state() {
    set_auto_switch_state "false" "" "" ""
}

compute_next_reset() {
    local reset_time reset_tz
    reset_time=$(get_auto_config_value "daily_reset_time")
    reset_tz=$(get_auto_config_value "daily_reset_timezone")
    [ -z "$reset_time" ] && return

    local now_epoch target_epoch today_date
    now_epoch=$(date +%s)

    today_date=$(TZ="$reset_tz" date "+%Y-%m-%d" 2>/dev/null || date "+%Y-%m-%d")
    target_epoch=$(TZ="$reset_tz" date -d "${today_date} ${reset_time}" "+%s" 2>/dev/null || echo "")

    if [ -z "$target_epoch" ]; then
        # macOS/BSD fallback
        target_epoch=$(python3 -c "
import datetime, zoneinfo
tz = zoneinfo.ZoneInfo('$reset_tz')
now = datetime.datetime.now(tz)
reset = now.replace(hour=${reset_time%%:*}, minute=${reset_time##*:}, second=0, microsecond=0)
if reset <= now:
    reset += datetime.timedelta(days=1)
print(int(reset.timestamp()))
" 2>/dev/null || echo "")
    else
        if [ "$target_epoch" -le "$now_epoch" ]; then
            target_epoch=$((target_epoch + 86400))
        fi
    fi

    if [ -n "$target_epoch" ]; then
        TZ="$reset_tz" date -d "@$target_epoch" "+%Y-%m-%dT%H:%M:%S%:z" 2>/dev/null || \
            date -r "$target_epoch" "+%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || \
            echo "$target_epoch"
    fi
}

is_past_reset_time() {
    local next_reset
    next_reset=$(get_auto_switch_state "next_reset")
    [ -z "$next_reset" ] && return 1

    local now_epoch reset_epoch
    now_epoch=$(date +%s)

    reset_epoch=$(date -d "$next_reset" "+%s" 2>/dev/null || echo "")
    if [ -z "$reset_epoch" ]; then
        case "$next_reset" in
            [0-9]*) reset_epoch="$next_reset" ;;
        esac
    fi

    [ -n "$reset_epoch" ] && [ "$now_epoch" -ge "$reset_epoch" ]
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
    local current
    current=$(get_config_value "active_profile")
    local primary
    primary=$(get_auto_config_value "primary_profile")

    local fallback
    fallback=$(get_next_fallback "$current") || {
        echo "error: no fallback profile available." >&2
        return 1
    }

    set_auto_switch_state "true" "${primary:-$current}" "$fallback" "$reason"
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

    clear_auto_switch_state
    cmd_use "$original"
}
