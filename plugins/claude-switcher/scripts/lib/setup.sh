# shellcheck shell=bash
# Setup, uninstall, and plugin configuration for claude-switcher
# Sourced by the main entry point -- not executed directly

STATUSLINE_SNIPPET_MARKER="# claude-switcher: capture rate limits"
STATUSLINE_AUTOSWITCH_MARKER="# claude-switcher: auto-switch"
STATUSLINE_PROFILE_MARKER="# claude-switcher: profile indicator"

cmd_setup() {
    echo "claude-switcher setup"
    echo "====================="
    echo ""

    ensure_dirs
    init_config

    local current_email=""
    if [ -f "$CLAUDE_CREDS" ] && [ -f "$CLAUDE_CONFIG" ]; then
        current_email=$(jq -r '.oauthAccount.emailAddress // empty' "$CLAUDE_CONFIG" 2>/dev/null)
    fi

    if [ -n "$current_email" ]; then
        echo "You are currently logged in as: $current_email"
        printf "Save this as your first profile? [Y/n] "
        read -r confirm
        case "$confirm" in
            [nN]|[nN][oO]) ;;
            *)
                printf "Profile name for this account: "
                read -r name1
                [ -z "$name1" ] && die "profile name cannot be empty."
                cmd_save "$name1"
                echo ""
                ;;
        esac
    else
        echo "You are not currently logged in."
        echo "Log in to your first account:"
        echo "  claude auth login"
        echo ""
        echo "Then re-run: claude-switcher setup"
        return 0
    fi

    echo "Now log in to your second account."
    echo "Run this command, then come back:"
    echo ""
    echo "  claude auth logout && claude auth login"
    echo ""
    printf "Press Enter when you're logged in to the second account..."
    read -r

    local new_email=""
    if [ -f "$CLAUDE_CONFIG" ]; then
        new_email=$(jq -r '.oauthAccount.emailAddress // empty' "$CLAUDE_CONFIG" 2>/dev/null)
    fi

    if [ -z "$new_email" ]; then
        die "doesn't look like you're logged in. Run 'claude auth login' and try again."
    fi

    if [ -n "$current_email" ] && [ "$new_email" = "$current_email" ]; then
        die "you're still logged in as $current_email. Log in with a different account."
    fi

    local new_uuid
    new_uuid=$(jq -r '.oauthAccount.accountUuid // empty' "$CLAUDE_CONFIG" 2>/dev/null)
    for profile_dir in "$PROFILES_DIR"/*/; do
        [ -d "$profile_dir" ] || continue
        local existing_uuid
        existing_uuid=$(jq -r '.accountUuid // empty' "${profile_dir}/account-metadata.json" 2>/dev/null)
        if [ "$new_uuid" = "$existing_uuid" ]; then
            die "this account (UUID: $new_uuid) is already saved as profile '$(basename "$profile_dir")'. Log in with a different account."
        fi
    done

    echo "Logged in as: $new_email"
    printf "Profile name for this account: "
    read -r name2
    [ -z "$name2" ] && die "profile name cannot be empty."
    cmd_save "$name2"
    echo ""

    echo "Available profiles:"
    cmd_list
    echo ""
    printf "Default profile to activate now: "
    read -r default_profile
    if [ -n "$default_profile" ] && profile_exists "$default_profile"; then
        cmd_use "$default_profile"
    else
        echo "No valid profile selected. You can switch later with: claude-switcher use <name>"
    fi

    echo ""
    echo "Setup complete. Switch anytime with: claude-switcher use <name>"
}

_install_profile_helper() {
    local helper_path="${SWITCHER_DIR}/statusline-profile.sh"
    cat > "$helper_path" <<'HELPER'
# claude-switcher: profile indicator helper
# Sourced by the status line script to set $_cs_indicator
_cs_indicator=""
_cs_show=$(jq -r '.show_in_statusline // false' ~/.claude-switcher/auto-switch.json 2>/dev/null)
if [ "$_cs_show" = "true" ]; then
    _cs_profile=$(jq -r '.active_profile // empty' ~/.claude-switcher/config.json 2>/dev/null)
    if [ -n "$_cs_profile" ]; then
        if [ -f ~/.claude-switcher/auto-switch-state.json ] && [ "$(jq -r '.on_fallback // false' ~/.claude-switcher/auto-switch-state.json 2>/dev/null)" = "true" ]; then
            _cs_indicator="[${_cs_profile} FALLBACK] "
        else
            _cs_indicator="[${_cs_profile}] "
        fi
    fi
fi
HELPER
    chmod 644 "$helper_path"
}

_install_autoswitch_helper() {
    local helper_path="${SWITCHER_DIR}/statusline-autoswitch.sh"
    cat > "$helper_path" <<'HELPER'
# claude-switcher: auto-switch helper
# Sourced by the status line script. Expects $input (raw JSON from Claude Code).
# Reads rate limits from $input, checks thresholds, spawns async switches.

_cs_autoswitch() {
    local config_file="$HOME/.claude-switcher/auto-switch.json"
    local state_file="$HOME/.claude-switcher/auto-switch-state.json"
    local config_main="$HOME/.claude-switcher/config.json"
    local cli="$HOME/.claude-switcher/cli"

    # Bail fast if auto-switch not configured or CLI not available
    [ -f "$config_file" ] || return 0
    [ -x "$cli" ] || [ -f "$cli" ] || return 0

    local enabled
    enabled=$(jq -r '.enabled // false' "$config_file" 2>/dev/null)
    [ "$enabled" = "true" ] || return 0

    # Read rate limits directly from the status line input JSON (freshest data)
    local five_pct seven_pct
    five_pct=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0' 2>/dev/null)
    seven_pct=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0' 2>/dev/null)

    # Truncate to integers
    five_pct=${five_pct%.*}; five_pct=${five_pct:-0}
    seven_pct=${seven_pct%.*}; seven_pct=${seven_pct:-0}

    local max_pct=$five_pct
    [ "$seven_pct" -gt "$max_pct" ] 2>/dev/null && max_pct=$seven_pct

    # Check current state
    local on_fallback="false"
    if [ -f "$state_file" ]; then
        on_fallback=$(jq -r '.on_fallback // false' "$state_file" 2>/dev/null)
    fi

    if [ "$on_fallback" = "true" ]; then
        # On fallback — check if primary's limits have reset
        local switch_back_at
        switch_back_at=$(jq -r '.switch_back_at // empty' "$state_file" 2>/dev/null)
        if [ -n "$switch_back_at" ] && [ "$switch_back_at" != "null" ]; then
            local now_epoch
            now_epoch=$(date +%s)
            if [ "$now_epoch" -ge "$switch_back_at" ] 2>/dev/null; then
                # Debounce: skip if a switch attempt is already in progress (lock file < 30s old)
                local lock_file="$HOME/.claude-switcher/.switch-back.lock"
                if [ -f "$lock_file" ]; then
                    local lock_age
                    lock_age=$(( now_epoch - $(stat -c %Y "$lock_file" 2>/dev/null || echo 0) ))
                    [ "$lock_age" -lt 30 ] && return 0
                fi
                touch "$lock_file" 2>/dev/null

                # Time to switch back — switch first, clear state only on success
                local original
                original=$(jq -r '.original_profile // empty' "$state_file" 2>/dev/null)
                if [ -n "$original" ]; then
                    (sh "$cli" use "$original" && sh "$cli" auto-config reset-state; rm -f "$lock_file") >> ~/.claude-switcher/switch.log 2>&1 &
                fi
            fi
        fi
    else
        # On primary — check if we need to preemptively switch
        local threshold
        threshold=$(jq -r '.preemptive_switch_percent // 97' "$config_file" 2>/dev/null)
        if [ "$max_pct" -ge "$threshold" ] 2>/dev/null; then
            # Threshold exceeded — spawn async switch
            (sh "$cli" check-limits >/dev/null 2>&1) &
        fi
    fi

    # Profile mismatch detection
    local active_profile live_email
    active_profile=$(jq -r '.active_profile // empty' "$config_main" 2>/dev/null)
    if [ -n "$active_profile" ] && [ -d "$HOME/.claude-switcher/profiles/$active_profile" ]; then
        live_email=$(printf '%s' "$input" | jq -r '.account.email // empty' 2>/dev/null)
        if [ -z "$live_email" ] && [ -f "$HOME/.claude.json" ]; then
            live_email=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)
        fi
        if [ -n "$live_email" ]; then
            local saved_email
            saved_email=$(jq -r '.emailAddress // empty' "$HOME/.claude-switcher/profiles/$active_profile/account-metadata.json" 2>/dev/null)
            if [ -n "$saved_email" ] && [ "$live_email" != "$saved_email" ]; then
                local matched=""
                for pdir in "$HOME/.claude-switcher/profiles"/*/; do
                    [ -d "$pdir" ] || continue
                    local pemail
                    pemail=$(jq -r '.emailAddress // empty' "${pdir}/account-metadata.json" 2>/dev/null)
                    if [ "$pemail" = "$live_email" ]; then
                        matched=$(basename "$pdir")
                        break
                    fi
                done
                if [ -n "$matched" ] && [ "$matched" != "$active_profile" ]; then
                    local tmp
                    tmp=$(mktemp "${config_main}.XXXXXX")
                    jq --arg p "$matched" --arg prev "$active_profile" \
                        '.active_profile = $p | .previous_profile = $prev' "$config_main" > "$tmp" \
                        && mv "$tmp" "$config_main"
                    chmod 600 "$config_main"
                fi
            fi
        fi
    fi
}

# Run only if $input is set (we're being sourced from a status line script)
if [ -n "${input:-}" ]; then
    _cs_autoswitch
fi
HELPER
    chmod 644 "$helper_path"
}

cmd_setup_plugin() {
    local claude_settings="${CLAUDE_DIR}/settings.json"
    local statusline_script="${CLAUDE_DIR}/statusline-command.sh"

    ensure_dirs

    echo "claude-switcher setup"
    echo "====================="
    echo ""

    # Always install/update helper scripts (idempotent)
    _install_autoswitch_helper
    _install_profile_helper
    echo "Helper scripts installed."

    local has_statusline=false
    if [ -f "$claude_settings" ]; then
        if jq -e '.statusLine' "$claude_settings" >/dev/null 2>&1; then
            has_statusline=true
        fi
    fi

    if [ "$has_statusline" = false ]; then
        echo "No status line configured. Creating one..."

        cat > "$statusline_script" <<STATUSLINE
#!/bin/sh
input=\$(cat)

# claude-switcher: capture rate limits
printf '%s' "\$input" | jq '{five_hour:.rate_limits.five_hour,seven_day:.rate_limits.seven_day}' > ~/.claude-switcher/rate-limits.json 2>/dev/null || true

# claude-switcher: auto-switch
. ${SWITCHER_DIR}/statusline-autoswitch.sh

# claude-switcher: profile indicator
. ${SWITCHER_DIR}/statusline-profile.sh

cwd=\$(echo "\$input" | jq -r '.cwd // empty')
model=\$(echo "\$input" | jq -r '.model.display_name // .model.id // "unknown"')
short_dir="\${cwd#"\${HOME}"}"
[ "\$short_dir" != "\$cwd" ] && short_dir="~\${short_dir}"
echo "\${_cs_indicator}\${short_dir} | \${model}"
STATUSLINE
        chmod +x "$statusline_script"

        if [ ! -f "$claude_settings" ]; then
            echo '{}' > "$claude_settings"
        fi
        local tmp
        tmp=$(mktemp "${claude_settings}.XXXXXX")
        jq '.statusLine = {"type": "command", "command": "bash ~/.claude/statusline-command.sh"}' "$claude_settings" > "$tmp" && mv "$tmp" "$claude_settings"
        echo "Created status line: $statusline_script"
    else
        local statusline_cmd
        statusline_cmd=$(jq -r '.statusLine.command // empty' "$claude_settings")

        local script_path=""
        # Extract path from "bash /path/to/script" or "/path/to/script"
        script_path=$(echo "$statusline_cmd" | sed -n 's/^bash[[:space:]]\{1,\}//p')
        if [ -z "$script_path" ]; then
            case "$statusline_cmd" in
                /*) script_path="$statusline_cmd" ;;
            esac
        fi
        # Expand ~
        case "$script_path" in
            "~"*) script_path="${HOME}${script_path#\~}" ;;
        esac

        if [ -z "$script_path" ] || [ ! -f "$script_path" ]; then
            echo "warning: could not find status line script at '$script_path'." >&2
            echo "  Check your statusLine config in $claude_settings" >&2
            echo "  Rate limit capture and auto-switch may not work." >&2
        else
            _inject_into_statusline "$script_path"
        fi
    fi

    echo ""
    echo "Setup complete. Auto-switch runs via the status line."
    echo ""
    echo "Next steps (if not done already):"
    echo "  1. Save profiles: /save <name>"
    echo "  2. Enable auto-switch:"
    echo "     /auto-config enable"
    echo "     /auto-config primary <name>"
    echo "     /auto-config fallback <name>"
    echo "     /auto-config threshold 97"
    echo "  3. Show profile in status line (optional):"
    echo "     /auto-config show-profile enable"
}

_inject_into_statusline() {
    local script_path="$1"

    # 1. Rate limit capture
    if grep -q "$STATUSLINE_SNIPPET_MARKER" "$script_path" 2>/dev/null; then
        echo "Rate limit capture: already configured"
    else
        echo "Injecting rate limit capture..."

        local inject_after=""
        if grep -q 'input=$(cat)' "$script_path"; then
            inject_after='input=$(cat)'
        elif grep -q '_stdin=$(cat)' "$script_path"; then
            inject_after='_stdin=$(cat)'
        fi

        if [ -z "$inject_after" ]; then
            echo "warning: could not find stdin read line in $script_path." >&2
            echo "  Add manually after the line that reads stdin." >&2
            return 0
        fi

        local tmp
        tmp=$(mktemp "${script_path}.XXXXXX")
        awk -v marker="$STATUSLINE_SNIPPET_MARKER" -v target="$inject_after" '
        {
            print
            if ($0 == target) {
                print ""
                print marker
                print "printf '\''%s'\'' \"$input\" | jq '\''{five_hour:.rate_limits.five_hour,seven_day:.rate_limits.seven_day}'\'' > ~/.claude-switcher/rate-limits.json 2>/dev/null || true"
            }
        }' "$script_path" > "$tmp" && mv "$tmp" "$script_path"
        chmod +x "$script_path"
        echo "Rate limit capture: injected"
    fi

    # 2. Auto-switch helper
    if grep -q "$STATUSLINE_AUTOSWITCH_MARKER" "$script_path" 2>/dev/null; then
        echo "Auto-switch: already configured"
    else
        echo "Injecting auto-switch..."
        local tmp
        tmp=$(mktemp "${script_path}.XXXXXX")
        awk -v marker="$STATUSLINE_SNIPPET_MARKER" -v as_marker="$STATUSLINE_AUTOSWITCH_MARKER" -v helper="$SWITCHER_DIR/statusline-autoswitch.sh" '
        {
            print
            if (index($0, marker) && !done_as) {
                getline; print
                print ""
                print as_marker
                print ". " helper
                done_as = 1
            }
        }' "$script_path" > "$tmp" && mv "$tmp" "$script_path"
        chmod +x "$script_path"
        echo "Auto-switch: injected"
    fi

    # 3. Profile indicator
    if grep -q "$STATUSLINE_PROFILE_MARKER" "$script_path" 2>/dev/null; then
        echo "Profile indicator: already configured"
    else
        echo "Injecting profile indicator..."
        local tmp
        tmp=$(mktemp "${script_path}.XXXXXX")
        awk -v marker="$STATUSLINE_AUTOSWITCH_MARKER" -v profile_marker="$STATUSLINE_PROFILE_MARKER" -v helper="$SWITCHER_DIR/statusline-profile.sh" '
        {
            print
            if (index($0, marker) && !done_pi) {
                getline; print
                print ""
                print profile_marker
                print ". " helper
                done_pi = 1
            }
        }' "$script_path" > "$tmp" && mv "$tmp" "$script_path"
        chmod +x "$script_path"
        echo "Profile indicator: injected"
    fi
}

cmd_uninstall() {
    echo "claude-switcher uninstall"
    echo "========================="
    echo ""

    printf "Remove saved profiles? [y/N] "
    read -r confirm
    case "$confirm" in
        [yY]|[yY][eE][sS])
            rm -rf "${SWITCHER_DIR:?}"
            echo "Removed all profiles and config from $SWITCHER_DIR"
            ;;
        *)
            echo "Profiles kept at $SWITCHER_DIR"
            ;;
    esac

    local settings_file="${CLAUDE_DIR}/settings.json"
    if [ -f "$settings_file" ]; then
        local plugin_path
        plugin_path=$(cd "$(dirname "$(dirname "$0")")" 2>/dev/null && pwd) || plugin_path=""
        if [ -n "$plugin_path" ] && jq -e ".plugins | index(\"$plugin_path\")" "$settings_file" >/dev/null 2>&1; then
            local tmp
            tmp=$(mktemp "${settings_file}.XXXXXX")
            jq --arg p "$plugin_path" '.plugins = (.plugins | map(select(. != $p)))' "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
            echo "Deregistered Claude Code plugin"
        fi
    fi

    echo "Uninstall complete. Remove the plugin from your Claude Code settings to fully unregister."
}
