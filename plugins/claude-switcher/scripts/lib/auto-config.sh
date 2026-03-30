# shellcheck shell=bash
# Auto-switch configuration commands for claude-switcher
# Sourced by the main entry point -- not executed directly

cmd_auto_config() {
    init_auto_switch_config

    local subcmd="${1:-show}"
    shift 2>/dev/null || true

    case "$subcmd" in
        show)
            echo "Auto-switch configuration:"
            echo ""
            local enabled primary
            enabled=$(get_auto_config_value "enabled")
            primary=$(get_auto_config_value "primary_profile")

            echo "  Enabled:        ${enabled:-false}"
            echo "  Primary:        ${primary:-(not set)}"

            local fallbacks threshold
            fallbacks=$(jq -r '.fallback_profiles | join(", ")' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
            threshold=$(get_auto_config_value "preemptive_switch_percent")

            echo "  Fallbacks:      ${fallbacks:-(none)}"
            echo "  Threshold:      ${threshold:-97}%"

            echo ""
            echo "  Rate limits:    $(format_rate_limits)"

            # Show resets_at from current rate-limits.json
            local five_resets seven_resets
            five_resets=$(get_rate_limit_resets_at "five_hour")
            seven_resets=$(get_rate_limit_resets_at "seven_day")
            if [ -n "$five_resets" ] || [ -n "$seven_resets" ]; then
                echo "  5h resets at:   $(format_resets_at "$five_resets")"
                echo "  7d resets at:   $(format_resets_at "$seven_resets")"
            fi

            if [ -f "$AUTO_SWITCH_STATE" ]; then
                local on_fb
                on_fb=$(get_auto_switch_state "on_fallback")
                if [ "$on_fb" = "true" ]; then
                    local orig fb_prof reason switch_back_at
                    orig=$(get_auto_switch_state "original_profile")
                    fb_prof=$(get_auto_switch_state "fallback_profile")
                    reason=$(get_auto_switch_state "reason")
                    switch_back_at=$(get_auto_switch_state "switch_back_at")
                    echo ""
                    echo "  ** ON FALLBACK **"
                    echo "  Original:       $orig"
                    echo "  Using:          $fb_prof"
                    echo "  Reason:         $reason"
                    echo "  Switches back:  $(format_resets_at "$switch_back_at")"
                fi
            fi
            ;;
        enable)
            set_auto_config_value "enabled" "true"
            echo "Auto-switch enabled."
            ;;
        disable)
            set_auto_config_value "enabled" "false"
            echo "Auto-switch disabled."
            ;;
        primary)
            local name="${1:-}"
            [ -z "$name" ] && die "usage: claude-switcher auto-config primary <profile-name>"
            validate_profile_name "$name"
            profile_exists "$name" || die "profile '$name' not found."
            set_auto_config_value "primary_profile" "$name"
            echo "Primary profile set to \"$name\""
            ;;
        fallback)
            local name="${1:-}"
            [ -z "$name" ] && die "usage: claude-switcher auto-config fallback <profile-name>"
            validate_profile_name "$name"
            profile_exists "$name" || die "profile '$name' not found."
            local current_fallbacks
            current_fallbacks=$(jq -c '.fallback_profiles // []' "$AUTO_SWITCH_CONFIG")
            local new_fallbacks
            new_fallbacks=$(echo "$current_fallbacks" | jq --arg n "$name" '. + [$n] | unique')
            set_auto_config_value "fallback_profiles" "$new_fallbacks"
            echo "Added \"$name\" to fallback profiles."
            ;;
        threshold)
            local pct="${1:-}"
            [ -z "$pct" ] && die "usage: claude-switcher auto-config threshold <percent>"
            if ! echo "$pct" | grep -qE '^[0-9]+$' || [ "$pct" -lt 1 ] || [ "$pct" -gt 100 ]; then
                die "threshold must be a number between 1 and 100."
            fi
            set_auto_config_value "preemptive_switch_percent" "$pct"
            echo "Preemptive switch threshold set to ${pct}%"
            ;;
        reset-state)
            clear_auto_switch_state
            echo "Auto-switch state cleared."
            ;;
        *)
            die "unknown auto-config subcommand: $subcmd. Use: show, enable, disable, primary, fallback, threshold, reset-state"
            ;;
    esac
}

cmd_limit_hit() {
    init_auto_switch_config
    local enabled
    enabled=$(get_auto_config_value "enabled")
    if [ "$enabled" != "true" ]; then
        die "auto-switch is not enabled. Run 'claude-switcher auto-config enable' first."
    fi

    local primary
    primary=$(get_auto_config_value "primary_profile")
    [ -z "$primary" ] && die "no primary profile configured. Run 'claude-switcher auto-config primary <name>' first."

    # Read current resets_at timestamps for switch-back timing
    local five_resets seven_resets switch_back_at
    five_resets=$(get_rate_limit_resets_at "five_hour")
    seven_resets=$(get_rate_limit_resets_at "seven_day")

    # For manual limit-hit, use the earliest resets_at as switch-back time
    switch_back_at=""
    if [ -n "$five_resets" ] && [ -n "$seven_resets" ]; then
        if [ "$five_resets" -le "$seven_resets" ] 2>/dev/null; then
            switch_back_at="$five_resets"
        else
            switch_back_at="$seven_resets"
        fi
    else
        switch_back_at="${five_resets:-$seven_resets}"
    fi

    echo "Rate limit hit. Switching to fallback..."
    do_auto_switch_to_fallback "rate_limit_manual" "$five_resets" "$seven_resets" "$switch_back_at"
}
