# shellcheck shell=bash
# Utility functions for claude-switcher
# Sourced by the main entry point -- not executed directly

die() {
    echo "error: $*" >&2
    exit 1
}

check_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        install_hint=""
        if command -v apt >/dev/null 2>&1; then
            install_hint="sudo apt install jq"
        elif command -v brew >/dev/null 2>&1; then
            install_hint="brew install jq"
        elif command -v dnf >/dev/null 2>&1; then
            install_hint="sudo dnf install jq"
        elif command -v pacman >/dev/null 2>&1; then
            install_hint="sudo pacman -S jq"
        fi
        die "jq is required but not installed.${install_hint:+ Install: $install_hint}"
    fi
}

ensure_dirs() {
    mkdir -p "$PROFILES_DIR" && chmod 700 "$SWITCHER_DIR" "$PROFILES_DIR"
    mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
}

init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo '{"active_profile":null,"previous_profile":null}' | jq . > "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
    fi
}

get_config_value() {
    jq -r ".$1 // empty" "$CONFIG_FILE" 2>/dev/null
}

set_config_value() {
    local key="$1" value="$2"
    local tmp
    tmp=$(mktemp "${CONFIG_FILE}.XXXXXX")
    jq --arg v "$value" ".$key = \$v" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

validate_profile_name() {
    local name="$1"
    case "$name" in
        *[!a-zA-Z0-9_-]*) die "invalid profile name '$name'. Use only letters, numbers, hyphens, and underscores." ;;
        '') die "profile name cannot be empty." ;;
    esac
}

profile_exists() {
    [ -d "${PROFILES_DIR}/$1" ] && [ -f "${PROFILES_DIR}/$1/credentials.json" ]
}

check_credentials_exist() {
    if [ ! -f "$CLAUDE_CREDS" ]; then
        die "no credentials found at $CLAUDE_CREDS. Log in first: claude auth login"
    fi
}

check_config_exists() {
    if [ ! -f "$CLAUDE_CONFIG" ]; then
        die "no config found at $CLAUDE_CONFIG. Claude Code may not be installed."
    fi
}

validate_json_file() {
    local file="$1" desc="$2"
    if ! jq empty "$file" 2>/dev/null; then
        die "$desc at $file is malformed JSON."
    fi
}

check_active_sessions() {
    local session_dir="${CLAUDE_DIR}/sessions"
    if [ -d "$session_dir" ]; then
        for session_file in "$session_dir"/*.json; do
            [ -f "$session_file" ] || continue
            local pid
            pid=$(jq -r '.pid // empty' "$session_file" 2>/dev/null)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                echo "warning: active Claude Code session detected (PID $pid). Switching mid-session may cause issues." >&2
                return 0
            fi
        done
    fi
}

format_timestamp() {
    date -d "@$1" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r "$1" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown"
}

check_token_expiry() {
    local creds_file="$1"
    local expires_at
    expires_at=$(jq -r '.claudeAiOauth.expiresAt // empty' "$creds_file" 2>/dev/null)
    if [ -n "$expires_at" ]; then
        local now_ms
        now_ms=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")
        if [ "$expires_at" -lt "$now_ms" ] 2>/dev/null; then
            return 1
        fi
    fi
    return 0
}

get_profile_email() {
    jq -r '.emailAddress // "unknown"' "$1" 2>/dev/null
}

get_profile_org() {
    jq -r '.organizationName // empty' "$1" 2>/dev/null
}

get_profile_sub() {
    local creds_file="$1" meta_file="$2"
    local sub
    sub=$(jq -r '.claudeAiOauth.subscriptionType // empty' "$creds_file" 2>/dev/null)
    if [ -z "$sub" ]; then
        sub=$(jq -r '.subscriptionType // "unknown"' "$meta_file" 2>/dev/null)
    fi
    echo "$sub"
}

format_profile_summary() {
    local creds_file="$1" meta_file="$2"
    local email org sub
    email=$(get_profile_email "$meta_file")
    org=$(get_profile_org "$meta_file")
    sub=$(get_profile_sub "$creds_file" "$meta_file")
    echo "${email}${org:+, $org}, ${sub} subscription"
}

backup_current_state() {
    if [ -f "$CLAUDE_CREDS" ]; then
        cp "$CLAUDE_CREDS" "${BACKUP_DIR}/credentials.json"
        chmod 600 "${BACKUP_DIR}/credentials.json"
    fi
    if [ -f "$CLAUDE_CONFIG" ]; then
        jq '.oauthAccount // empty' "$CLAUDE_CONFIG" > "${BACKUP_DIR}/account-metadata.json" 2>/dev/null
        chmod 600 "${BACKUP_DIR}/account-metadata.json"
    fi
}
