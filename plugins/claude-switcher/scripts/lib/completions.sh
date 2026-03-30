# shellcheck shell=bash
# Shell completion generators for claude-switcher
# Sourced by the main entry point -- not executed directly

cmd_completions() {
    local shell="${1:-bash}"
    case "$shell" in
        bash)
            cat <<'BASH_COMP'
_claude_switcher() {
    local cur prev commands profiles
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    commands="save use prev list show status delete rename setup setup-plugin auto-config limit-hit uninstall help version completions"

    case "$prev" in
        use|delete|show)
            profiles=$(ls "${HOME}/.claude-switcher/profiles/" 2>/dev/null)
            COMPREPLY=($(compgen -W "$profiles" -- "$cur"))
            return 0
            ;;
        rename)
            if [ "$COMP_CWORD" -eq 2 ]; then
                profiles=$(ls "${HOME}/.claude-switcher/profiles/" 2>/dev/null)
                COMPREPLY=($(compgen -W "$profiles" -- "$cur"))
            fi
            return 0
            ;;
        claude-switcher)
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            return 0
            ;;
    esac

    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
}
complete -F _claude_switcher claude-switcher
BASH_COMP
            ;;
        zsh)
            cat <<'ZSH_COMP'
#compdef claude-switcher

_claude_switcher() {
    local -a commands profiles
    commands=(
        'save:Save current auth as a named profile'
        'use:Switch to a saved profile'
        'prev:Switch to previous profile'
        'list:List all saved profiles'
        'show:Show profile details'
        'status:Show active profile and auth status'
        'delete:Delete a saved profile'
        'rename:Rename a profile'
        'setup:Interactive first-time setup'
        'setup-plugin:Set up rate limit capture'
        'auto-config:Configure auto-switching'
        'limit-hit:Trigger fallback switch'
        'uninstall:Remove claude-switcher'
        'help:Show help'
        'version:Show version'
        'completions:Generate shell completions'
    )

    _get_profiles() {
        local -a profiles
        profiles=(${(f)"$(ls "${HOME}/.claude-switcher/profiles/" 2>/dev/null)"})
        _describe 'profile' profiles
    }

    case "$words[2]" in
        use|delete|show)
            _get_profiles
            ;;
        rename)
            if (( CURRENT == 3 )); then
                _get_profiles
            fi
            ;;
        *)
            _describe 'command' commands
            ;;
    esac
}

_claude_switcher "$@"
ZSH_COMP
            ;;
        *)
            die "unknown shell: $shell. Supported: bash, zsh"
            ;;
    esac
}
