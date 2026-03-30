# shellcheck shell=bash
# Shared variables for claude-switcher
# Sourced by the main entry point -- not executed directly
# shellcheck disable=SC2034

VERSION="2.0.0"

CLAUDE_DIR="${HOME}/.claude"
CLAUDE_CREDS="${CLAUDE_DIR}/.credentials.json"
CLAUDE_CONFIG="${HOME}/.claude.json"
SWITCHER_DIR="${HOME}/.claude-switcher"
PROFILES_DIR="${SWITCHER_DIR}/profiles"
CONFIG_FILE="${SWITCHER_DIR}/config.json"
BACKUP_DIR="${SWITCHER_DIR}/.last-state"
AUTO_SWITCH_CONFIG="${SWITCHER_DIR}/auto-switch.json"
AUTO_SWITCH_STATE="${SWITCHER_DIR}/auto-switch-state.json"
RATE_LIMITS_FILE="${SWITCHER_DIR}/rate-limits.json"
