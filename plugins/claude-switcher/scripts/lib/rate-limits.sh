# shellcheck shell=bash
# Rate limit monitoring for claude-switcher
# Sourced by the main entry point -- not executed directly

get_rate_limit_five_hour() {
    if [ -f "$RATE_LIMITS_FILE" ]; then
        jq -r '.five_hour.used_percentage // 0' "$RATE_LIMITS_FILE" 2>/dev/null
    else
        echo "0"
    fi
}

get_rate_limit_seven_day() {
    if [ -f "$RATE_LIMITS_FILE" ]; then
        jq -r '.seven_day.used_percentage // 0' "$RATE_LIMITS_FILE" 2>/dev/null
    else
        echo "0"
    fi
}

get_rate_limit_resets_at() {
    local window="$1"
    if [ -f "$RATE_LIMITS_FILE" ]; then
        jq -r ".${window}.resets_at // empty" "$RATE_LIMITS_FILE" 2>/dev/null
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

save_rate_limits_for_active_profile() {
    [ -f "$RATE_LIMITS_FILE" ] || return 0
    local active
    active=$(get_config_value "active_profile")
    [ -z "$active" ] || [ ! -d "${PROFILES_DIR}/${active}" ] && return 0
    cp "$RATE_LIMITS_FILE" "${PROFILES_DIR}/${active}/rate-limits.json" 2>/dev/null || true
}

get_profile_rate_limits_file() {
    local profile="$1"
    echo "${PROFILES_DIR}/${profile}/rate-limits.json"
}

check_rate_limits_and_switch() {
    init_auto_switch_config

    local enabled
    enabled=$(get_auto_config_value "enabled")
    if [ "$enabled" != "true" ]; then
        return
    fi

    # Save current rate limits to active profile
    save_rate_limits_for_active_profile

    # If on fallback, check if primary's limits have reset
    if [ -f "$AUTO_SWITCH_STATE" ]; then
        local on_fb
        on_fb=$(get_auto_switch_state "on_fallback")
        if [ "$on_fb" = "true" ]; then
            check_primary_reset_and_switch_back
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
        local five_hour seven_day five_int seven_int
        five_hour=$(get_rate_limit_five_hour)
        seven_day=$(get_rate_limit_seven_day)
        five_int=${five_hour%.*}; five_int=${five_int:-0}
        seven_int=${seven_day%.*}; seven_int=${seven_int:-0}

        # Determine which resets_at to use: max of all windows above threshold
        local five_resets seven_resets switch_back_at
        five_resets=$(get_rate_limit_resets_at "five_hour")
        seven_resets=$(get_rate_limit_resets_at "seven_day")

        switch_back_at=""
        if [ "$five_int" -ge "$threshold" ] 2>/dev/null && [ -n "$five_resets" ]; then
            switch_back_at="$five_resets"
        fi
        if [ "$seven_int" -ge "$threshold" ] 2>/dev/null && [ -n "$seven_resets" ]; then
            if [ -z "$switch_back_at" ] || [ "$seven_resets" -gt "$switch_back_at" ] 2>/dev/null; then
                switch_back_at="$seven_resets"
            fi
        fi
        # Fallback: use earliest available resets_at if we couldn't determine
        if [ -z "$switch_back_at" ]; then
            if [ -n "$five_resets" ] && [ -n "$seven_resets" ]; then
                if [ "$five_resets" -le "$seven_resets" ] 2>/dev/null; then
                    switch_back_at="$five_resets"
                else
                    switch_back_at="$seven_resets"
                fi
            else
                switch_back_at="${five_resets:-$seven_resets}"
            fi
        fi

        do_auto_switch_to_fallback "preemptive_5h:${five_hour}%_7d:${seven_day}%" "$five_resets" "$seven_resets" "$switch_back_at" 2>&1 || true
    fi
}

check_primary_reset_and_switch_back() {
    local switch_back_at
    switch_back_at=$(get_auto_switch_state "switch_back_at")
    [ -z "$switch_back_at" ] && return 0

    local now_epoch
    now_epoch=$(date +%s)
    if [ "$now_epoch" -ge "$switch_back_at" ] 2>/dev/null; then
        do_auto_switch_back 2>&1 || true
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

format_resets_at() {
    local epoch="$1"
    [ -z "$epoch" ] && echo "(unknown)" && return
    TZ="${2:-UTC}" date -d "@$epoch" "+%Y-%m-%d %H:%M %Z" 2>/dev/null || \
        date -r "$epoch" "+%Y-%m-%d %H:%M %Z" 2>/dev/null || \
        echo "$epoch"
}
