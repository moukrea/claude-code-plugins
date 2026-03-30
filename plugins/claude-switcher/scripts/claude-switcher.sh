#!/bin/sh
set -eu

# claude-switcher -- Switch between multiple Claude Code accounts
# Entry point: sources library modules and dispatches commands

# Resolve symlinks to find the real script location
_self="$0"
if [ -L "$_self" ]; then
    _self="$(readlink -f "$_self" 2>/dev/null || readlink "$_self")"
fi
SCRIPT_DIR="$(cd "$(dirname "$_self")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source library modules in dependency order
. "${LIB_DIR}/vars.sh"
. "${LIB_DIR}/helpers.sh"
. "${LIB_DIR}/profiles.sh"
. "${LIB_DIR}/auto-state.sh"
. "${LIB_DIR}/rate-limits.sh"
. "${LIB_DIR}/auto-config.sh"
. "${LIB_DIR}/status.sh"
. "${LIB_DIR}/setup.sh"
. "${LIB_DIR}/completions.sh"

cmd_help() {
    cat <<'HELP'
Usage: claude-switcher <command> [options]

Switch between multiple Claude Code accounts instantly.
Auto-switches on rate limits and switches back at reset time.

Commands:
  save <name> [--force]     Save current auth state as a named profile
  use <name>                Switch to a saved profile
  prev, -                   Switch to the previous profile
  list                      List all saved profiles
  show <name>               Show details of a profile
  status                    Show active profile and live auth status
  delete <name>             Delete a saved profile
  rename <old> <new>        Rename a profile
  setup                     Interactive first-time setup

Auto-switch:
  setup-plugin              Set up auto-switch in status line
  auto-config [subcmd]      Configure auto-switching
    show                    Show config, rate limits, and state
    enable / disable        Toggle auto-switching
    primary <name>          Set primary (preferred) profile
    fallback <name>         Add a fallback profile
    threshold <percent>     Set preemptive switch % (default: 97)
    show-profile on/off     Toggle profile indicator in status line
    reset-state             Clear auto-switch state
  limit-hit                 Manually trigger fallback switch

Other:
  uninstall                 Remove claude-switcher
  help                      Show this help
  version                   Show version
HELP
}

cmd_version() {
    echo "claude-switcher $VERSION"
}

main() {
    check_jq
    ensure_dirs
    init_config

    cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$cmd" in
        save)        cmd_save "$@" ;;
        use)         cmd_use "${1:-}" ;;
        prev|-)      cmd_prev ;;
        list|ls)     cmd_list ;;
        show)        cmd_show "${1:-}" ;;
        status)      cmd_status ;;
        delete|rm)   cmd_delete "${1:-}" ;;
        rename|mv)   cmd_rename "${1:-}" "${2:-}" ;;
        setup)       cmd_setup ;;
        auto-config) cmd_auto_config "${1:-show}" "${2:-}" "${3:-}" ;;
        limit-hit)   cmd_limit_hit ;;
        check-limits) check_rate_limits_and_switch ;;
        setup-plugin) cmd_setup_plugin ;;
        uninstall)   cmd_uninstall ;;
        completions) cmd_completions "${1:-bash}" ;;
        help|--help|-h) cmd_help ;;
        version|--version|-v) cmd_version ;;
        *)           die "unknown command: $cmd. Run 'claude-switcher help' for usage." ;;
    esac
}

main "$@"
