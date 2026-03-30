# shellcheck shell=bash
# Setup, uninstall, and plugin configuration for claude-switcher
# Sourced by the main entry point -- not executed directly

STATUSLINE_SNIPPET_MARKER="# claude-switcher: capture rate limits"

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

cmd_setup_plugin() {
    local claude_settings="${CLAUDE_DIR}/settings.json"
    local statusline_script="${CLAUDE_DIR}/statusline-command.sh"

    ensure_dirs

    echo "claude-switcher setup"
    echo "====================="
    echo ""

    local has_statusline=false
    if [ -f "$claude_settings" ]; then
        if jq -e '.statusLine' "$claude_settings" >/dev/null 2>&1; then
            has_statusline=true
        fi
    fi

    if [ "$has_statusline" = false ]; then
        echo "No status line configured. Creating one..."

        cat > "$statusline_script" <<'STATUSLINE'
#!/bin/sh
input=$(cat)

# claude-switcher: capture rate limits
printf '%s' "$input" | jq '{five_hour:.rate_limits.five_hour,seven_day:.rate_limits.seven_day}' > ~/.claude-switcher/rate-limits.json 2>/dev/null || true

cwd=$(echo "$input" | jq -r '.cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
short_dir="${cwd#"${HOME}"}"
[ "$short_dir" != "$cwd" ] && short_dir="~${short_dir}"
echo "${short_dir} | ${model}"
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
            die "could not find status line script at '$script_path'. Check your statusLine config in $claude_settings"
        fi

        if grep -q "$STATUSLINE_SNIPPET_MARKER" "$script_path" 2>/dev/null; then
            echo "Rate limit capture already configured in $script_path"
        else
            echo "Injecting rate limit capture into $script_path..."

            local inject_after=""
            if grep -q 'input=$(cat)' "$script_path"; then
                inject_after='input=$(cat)'
            elif grep -q '_stdin=$(cat)' "$script_path"; then
                inject_after='_stdin=$(cat)'
            fi

            if [ -z "$inject_after" ]; then
                die "could not find stdin read line in $script_path. Add manually after the line that reads stdin."
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
            echo "Injected rate limit capture after '${inject_after}'"
        fi
    fi

    echo ""
    echo "Rate limit data will be captured to: $RATE_LIMITS_FILE"
    echo "The status line updates this file continuously."
    echo ""
    echo "Next steps:"
    echo "  1. Save your profiles (if not done already)"
    echo "  2. Configure auto-switch:"
    local script_dir
    script_dir=$(dirname "$0")
    echo "     ${script_dir}/claude-switcher.sh auto-config enable"
    echo "     ${script_dir}/claude-switcher.sh auto-config primary work"
    echo "     ${script_dir}/claude-switcher.sh auto-config fallback personal"
    echo "     ${script_dir}/claude-switcher.sh auto-config threshold 97"
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
