# shellcheck shell=bash
# Status command for claude-switcher
# Sourced by the main entry point -- not executed directly

cmd_status() {
    local active
    active=$(get_config_value "active_profile")

    if [ -z "$active" ]; then
        echo "No active profile tracked by claude-switcher."
    else
        echo "Active profile: ${active}"
        cmd_show "$active"
    fi

    init_auto_switch_config
    local auto_enabled
    auto_enabled=$(get_auto_config_value "enabled")
    echo ""
    echo "Auto-switch: ${auto_enabled:-disabled}"
    if [ "$auto_enabled" = "true" ]; then
        local primary
        primary=$(get_auto_config_value "primary_profile")
        echo "  Primary:      ${primary:-(not set)}"
        local fallbacks
        fallbacks=$(jq -r '.fallback_profiles | join(", ")' "$AUTO_SWITCH_CONFIG" 2>/dev/null)
        echo "  Fallbacks:    ${fallbacks:-(none)}"

        local threshold
        threshold=$(get_auto_config_value "preemptive_switch_percent")
        echo "  Threshold:    ${threshold:-97}%"
        echo "  Rate limits:  $(format_rate_limits)"

        if [ -f "$AUTO_SWITCH_STATE" ]; then
            local on_fb
            on_fb=$(get_auto_switch_state "on_fallback")
            if [ "$on_fb" = "true" ]; then
                local orig reason next
                orig=$(get_auto_switch_state "original_profile")
                reason=$(get_auto_switch_state "reason")
                next=$(get_auto_switch_state "next_reset")
                echo "  ** ON FALLBACK (was: $orig, reason: $reason) **"
                echo "  Next reset:   ${next:-(unknown)}"
            fi
        fi
    fi

    echo ""
    echo "Live auth status:"
    if command -v claude >/dev/null 2>&1; then
        local live_status
        live_status=$(claude auth status --json 2>/dev/null || echo '{}')
        local live_email live_org live_sub live_logged_in
        live_logged_in=$(echo "$live_status" | jq -r '.loggedIn // false')
        if [ "$live_logged_in" = "true" ]; then
            live_email=$(echo "$live_status" | jq -r '.email // "unknown"')
            live_org=$(echo "$live_status" | jq -r '.orgName // empty')
            live_sub=$(echo "$live_status" | jq -r '.subscriptionType // "unknown"')
            echo "  Logged in:    yes"
            echo "  Email:        $live_email"
            [ -n "$live_org" ] && echo "  Organization: $live_org"
            echo "  Subscription: $live_sub"

            if [ -n "$active" ] && profile_exists "$active"; then
                local profile_email
                profile_email=$(jq -r '.emailAddress // empty' "${PROFILES_DIR}/${active}/account-metadata.json")
                if [ "$live_email" != "$profile_email" ]; then
                    echo ""
                    echo "warning: live auth email ($live_email) doesn't match active profile email ($profile_email)"
                fi
            fi
        else
            echo "  Logged in:    no"
        fi
    else
        echo "  (claude CLI not found)"
    fi
}
