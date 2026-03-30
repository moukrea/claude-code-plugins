# shellcheck shell=bash
# Profile management commands for claude-switcher
# Sourced by the main entry point -- not executed directly

cmd_save() {
    local name="" force=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --force|-f) force=true; shift ;;
            -*) die "unknown option: $1" ;;
            *) name="$1"; shift ;;
        esac
    done

    [ -z "$name" ] && die "usage: claude-switcher save <profile-name> [--force]"
    validate_profile_name "$name"
    check_credentials_exist
    check_config_exists
    validate_json_file "$CLAUDE_CREDS" "credentials"
    validate_json_file "$CLAUDE_CONFIG" "config"

    if profile_exists "$name" && [ "$force" != true ]; then
        die "profile '$name' already exists. Use --force to overwrite."
    fi

    local profile_dir="${PROFILES_DIR}/${name}"
    mkdir -p "$profile_dir" && chmod 700 "$profile_dir"

    cp "$CLAUDE_CREDS" "${profile_dir}/credentials.json"
    chmod 600 "${profile_dir}/credentials.json"

    jq '.oauthAccount // {}' "$CLAUDE_CONFIG" > "${profile_dir}/account-metadata.json"
    chmod 600 "${profile_dir}/account-metadata.json"

    echo "{\"saved_at\":$(date +%s),\"last_used\":$(date +%s)}" | jq . > "${profile_dir}/meta.json"
    chmod 600 "${profile_dir}/meta.json"

    set_config_value "active_profile" "$name"

    local summary
    summary=$(format_profile_summary "${profile_dir}/credentials.json" "${profile_dir}/account-metadata.json")
    echo "Saved profile \"${name}\" ($summary)"
}

cmd_use() {
    local name="$1"
    [ -z "${name:-}" ] && die "usage: claude-switcher use <profile-name>"

    if [ "$name" = "prev" ] || [ "$name" = "-" ]; then
        name=$(get_config_value "previous_profile")
        [ -z "$name" ] && die "no previous profile to switch to."
    fi

    validate_profile_name "$name"
    profile_exists "$name" || die "profile '$name' not found. Run 'claude-switcher list' to see available profiles."

    local current
    current=$(get_config_value "active_profile")
    if [ "$current" = "$name" ]; then
        echo "Already on profile \"${name}\""
        return 0
    fi

    local profile_dir="${PROFILES_DIR}/${name}"

    validate_json_file "${profile_dir}/credentials.json" "profile credentials"
    validate_json_file "${profile_dir}/account-metadata.json" "profile account metadata"

    if ! check_token_expiry "${profile_dir}/credentials.json"; then
        echo "warning: tokens in profile '$name' appear expired. You may need to re-authenticate and re-save." >&2
    fi

    check_active_sessions

    backup_current_state

    check_config_exists
    local tmp_creds tmp_config
    tmp_creds=$(mktemp "${CLAUDE_CREDS}.XXXXXX")
    cp "${profile_dir}/credentials.json" "$tmp_creds"
    chmod 600 "$tmp_creds"
    mv "$tmp_creds" "$CLAUDE_CREDS"

    local account_data
    account_data=$(cat "${profile_dir}/account-metadata.json")
    tmp_config=$(mktemp "${CLAUDE_CONFIG}.XXXXXX")
    jq --argjson acct "$account_data" '.oauthAccount = $acct' "$CLAUDE_CONFIG" > "$tmp_config"
    chmod 600 "$tmp_config"
    mv "$tmp_config" "$CLAUDE_CONFIG"

    if [ -n "$current" ]; then
        set_config_value "previous_profile" "$current"
    fi
    set_config_value "active_profile" "$name"

    local meta_file="${profile_dir}/meta.json"
    if [ -f "$meta_file" ]; then
        local tmp_meta
        tmp_meta=$(mktemp "${meta_file}.XXXXXX")
        jq --arg ts "$(date +%s)" '.last_used = ($ts | tonumber)' "$meta_file" > "$tmp_meta" && mv "$tmp_meta" "$meta_file"
        chmod 600 "$meta_file"
    fi

    local summary
    summary=$(format_profile_summary "${profile_dir}/credentials.json" "${profile_dir}/account-metadata.json")
    echo "Switched to profile \"${name}\" ($summary)"
}

cmd_list() {
    if [ ! -d "$PROFILES_DIR" ] || [ -z "$(ls -A "$PROFILES_DIR" 2>/dev/null)" ]; then
        echo "No profiles saved. Run 'claude-switcher save <name>' to create one."
        return 0
    fi

    local active
    active=$(get_config_value "active_profile")

    printf "%-2s %-15s %-35s %-20s %s\n" "" "PROFILE" "EMAIL" "ORG" "TYPE"
    for profile_dir in "$PROFILES_DIR"/*/; do
        [ -d "$profile_dir" ] || continue
        local name
        name=$(basename "$profile_dir")
        local meta_file="${profile_dir}/account-metadata.json"
        [ -f "$meta_file" ] || continue

        local creds_file="${profile_dir}/credentials.json"
        local email org sub marker=""
        email=$(get_profile_email "$meta_file")
        org=$(get_profile_org "$meta_file")
        [ -z "$org" ] && org="-"
        sub=$(get_profile_sub "$creds_file" "$meta_file")

        if [ "$name" = "$active" ]; then
            marker="*"
        fi

        printf "%-2s %-15s %-35s %-20s %s\n" "$marker" "$name" "$email" "$org" "$sub"
    done
}

cmd_delete() {
    local name="$1"
    [ -z "${name:-}" ] && die "usage: claude-switcher delete <profile-name>"
    validate_profile_name "$name"
    profile_exists "$name" || die "profile '$name' not found."

    local active
    active=$(get_config_value "active_profile")
    if [ "$name" = "$active" ]; then
        printf "Profile '%s' is currently active. Delete anyway? [y/N] " "$name"
        read -r confirm
        case "$confirm" in
            [yY]|[yY][eE][sS]) ;;
            *) echo "Cancelled."; return 0 ;;
        esac
        set_config_value "active_profile" ""
    fi

    rm -rf "${PROFILES_DIR:?}/${name}"
    echo "Deleted profile \"${name}\""
}

cmd_rename() {
    local old_name="${1:-}" new_name="${2:-}"
    [ -z "$old_name" ] || [ -z "$new_name" ] && die "usage: claude-switcher rename <old-name> <new-name>"
    validate_profile_name "$old_name"
    validate_profile_name "$new_name"
    profile_exists "$old_name" || die "profile '$old_name' not found."
    profile_exists "$new_name" && die "profile '$new_name' already exists."

    mv "${PROFILES_DIR}/${old_name}" "${PROFILES_DIR}/${new_name}"

    local active previous
    active=$(get_config_value "active_profile")
    previous=$(get_config_value "previous_profile")
    [ "$active" = "$old_name" ] && set_config_value "active_profile" "$new_name"
    [ "$previous" = "$old_name" ] && set_config_value "previous_profile" "$new_name"

    echo "Renamed profile \"${old_name}\" to \"${new_name}\""
}

cmd_show() {
    local name="${1:-}"
    [ -z "$name" ] && die "usage: claude-switcher show <profile-name>"
    validate_profile_name "$name"
    profile_exists "$name" || die "profile '$name' not found."

    local profile_dir="${PROFILES_DIR}/${name}"
    local meta_file="${profile_dir}/account-metadata.json"
    local creds_file="${profile_dir}/credentials.json"
    local info_file="${profile_dir}/meta.json"

    local active
    active=$(get_config_value "active_profile")
    local active_marker=""
    [ "$name" = "$active" ] && active_marker=" (active)"

    echo "Profile: ${name}${active_marker}"

    if [ -f "$meta_file" ]; then
        local email org sub display_name
        email=$(get_profile_email "$meta_file")
        org=$(get_profile_org "$meta_file")
        sub=$(get_profile_sub "$creds_file" "$meta_file")
        display_name=$(jq -r '.displayName // empty' "$meta_file")
        echo "  Email:        $email"
        [ -n "$display_name" ] && echo "  Display Name: $display_name"
        [ -n "$org" ] && echo "  Organization: $org"
        echo "  Subscription: $sub"
    fi

    if [ -f "$creds_file" ]; then
        local tier expires_at
        tier=$(jq -r '.claudeAiOauth.rateLimitTier // "unknown"' "$creds_file")
        expires_at=$(jq -r '.claudeAiOauth.expiresAt // empty' "$creds_file")
        echo "  Rate Limit:   $tier"
        if [ -n "$expires_at" ]; then
            local expires_sec=$((expires_at / 1000))
            echo "  Token Expiry: $(format_timestamp "$expires_sec")"
            if ! check_token_expiry "$creds_file"; then
                echo "  ** TOKEN EXPIRED ** -- re-authenticate and re-save this profile"
            fi
        fi
    fi

    if [ -f "$info_file" ]; then
        local saved_at last_used
        saved_at=$(jq -r '.saved_at // empty' "$info_file")
        last_used=$(jq -r '.last_used // empty' "$info_file")
        [ -n "$saved_at" ] && echo "  Saved:        $(format_timestamp "$saved_at")"
        [ -n "$last_used" ] && echo "  Last Used:    $(format_timestamp "$last_used")"
    fi
}

cmd_prev() {
    cmd_use "prev"
}
