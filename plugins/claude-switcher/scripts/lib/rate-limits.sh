# shellcheck shell=bash
# Rate limit monitoring for claude-switcher
# Sourced by the main entry point -- not executed directly

get_rate_limit_five_hour() {
    if [ -f "$RATE_LIMITS_FILE" ]; then
        jq -r '.five_hour.percent // 0' "$RATE_LIMITS_FILE" 2>/dev/null
    else
        echo "0"
    fi
}

get_rate_limit_seven_day() {
    if [ -f "$RATE_LIMITS_FILE" ]; then
        jq -r '.seven_day.percent // 0' "$RATE_LIMITS_FILE" 2>/dev/null
    else
        echo "0"
    fi
}

get_max_rate_limit_percent() {
    local five_hour seven_day
    five_hour=$(get_rate_limit_five_hour)
    seven_day=$(get_rate_limit_seven_day)
    local five_int seven_int
    five_int=${five_hour%.*}
    seven_int=${seven_day%.*}
    five_int=${five_int:-0}
    seven_int=${seven_int:-0}
    if [ "$five_int" -ge "$seven_int" ] 2>/dev/null; then
        echo "$five_int"
    else
        echo "$seven_int"
    fi
}

check_rate_limits_and_switch() {
    init_auto_switch_config

    local enabled
    enabled=$(get_auto_config_value "enabled")
    if [ "$enabled" != "true" ]; then
        return
    fi

    if [ -f "$AUTO_SWITCH_STATE" ]; then
        local on_fb
        on_fb=$(get_auto_switch_state "on_fallback")
        if [ "$on_fb" = "true" ]; then
            return
        fi
    fi

    if [ ! -f "$RATE_LIMITS_FILE" ]; then
        return
    fi

    local threshold max_pct
    threshold=$(get_auto_config_value "preemptive_switch_percent")
    threshold="${threshold:-97}"
    max_pct=$(get_max_rate_limit_percent)

    if [ "$max_pct" -ge "$threshold" ] 2>/dev/null; then
        local five_hour seven_day
        five_hour=$(get_rate_limit_five_hour)
        seven_day=$(get_rate_limit_seven_day)
        do_auto_switch_to_fallback "preemptive_5h:${five_hour}%_7d:${seven_day}%" 2>&1 || true
    fi
}

format_rate_limits() {
    if [ ! -f "$RATE_LIMITS_FILE" ]; then
        echo "(no data -- run /setup to enable rate limit capture)"
        return
    fi
    local five_hour seven_day
    five_hour=$(get_rate_limit_five_hour)
    seven_day=$(get_rate_limit_seven_day)
    echo "5h: ${five_hour}%, 7d: ${seven_day}%"
}
