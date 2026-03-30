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
            local enabled primary daily_time daily_tz weekly_day weekly_time
            enabled=$(get_auto_config_value "enabled")
            primary=$(get_auto_config_value "primary_profile")
            daily_time=$(get_auto_config_value "daily_reset_time")
            daily_tz=$(get_auto_config_value "daily_reset_timezone")
            weekly_day=$(get_auto_config_value "weekly_reset_day")
            weekly_time=$(get_auto_config_value "weekly_reset_time")

            echo "  Enabled:        ${enabled:-false}"
            echo "  Primary:        ${primary:-(not set)}"

            local fallbacks threshold
            fallbacks=$(jq -r '.fallback_profiles | join(", ")' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
            threshold=$(get_auto_config_value "preemptive_switch_percent")

            echo "  Fallbacks:      ${fallbacks:-(none)}"
            echo "  Threshold:      ${threshold:-97}%"
            echo "  Daily reset:    ${daily_time} ${daily_tz}"
            echo "  Weekly reset:   ${weekly_day} ${weekly_time} ${daily_tz}"

            echo ""
            echo "  Rate limits:    $(format_rate_limits)"

            if [ -f "$AUTO_SWITCH_STATE" ]; then
                local on_fb
                on_fb=$(get_auto_switch_state "on_fallback")
                if [ "$on_fb" = "true" ]; then
                    local orig fb_prof reason next
                    orig=$(get_auto_switch_state "original_profile")
                    fb_prof=$(get_auto_switch_state "fallback_profile")
                    reason=$(get_auto_switch_state "reason")
                    next=$(get_auto_switch_state "next_reset")
                    echo ""
                    echo "  ** ON FALLBACK **"
                    echo "  Original:       $orig"
                    echo "  Using:          $fb_prof"
                    echo "  Reason:         $reason"
                    echo "  Next reset:     ${next:-(unknown)}"
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
        daily-reset)
            local time="${1:-}" tz="${2:-}"
            [ -z "$time" ] && die "usage: claude-switcher auto-config daily-reset <HH:MM> [timezone]"
            if ! echo "$time" | grep -qE '^[0-9]{1,2}:[0-9]{2}$'; then
                die "invalid time format. Use HH:MM (e.g., 15:00)"
            fi
            local hour=${time%%:*} min=${time##*:}
            if [ "$hour" -gt 23 ] || [ "$min" -gt 59 ]; then
                die "invalid time '$time'. Hours must be 0-23, minutes 0-59."
            fi
            set_auto_config_value "daily_reset_time" "$time"
            [ -n "$tz" ] && set_auto_config_value "daily_reset_timezone" "$tz"
            echo "Daily reset set to $time${tz:+ ($tz)}"
            ;;
        weekly-reset)
            local day="${1:-}" time="${2:-}"
            [ -z "$day" ] && die "usage: claude-switcher auto-config weekly-reset <day> [HH:MM]"
            set_auto_config_value "weekly_reset_day" "$day"
            [ -n "$time" ] && set_auto_config_value "weekly_reset_time" "$time"
            echo "Weekly reset set to $day${time:+ at $time}"
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
            die "unknown auto-config subcommand: $subcmd. Use: show, enable, disable, primary, fallback, threshold, daily-reset, weekly-reset, reset-state"
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

    echo "Rate limit hit. Switching to fallback..."
    do_auto_switch_to_fallback "rate_limit_manual"
}
