#!/usr/bin/env bash
# provider-detect.sh — Detect git remote provider and available CLI tools.
# Meant to be sourced, not executed directly.

# Guard against double-sourcing.
[[ -n "${_GM_PROVIDER_DETECT_LOADED:-}" ]] && return 0

# Results (populated by gm_detect_provider / gm_parse_remote_url).
GM_REMOTE_OWNER=""
GM_REMOTE_REPO=""

# ---------------------------------------------------------------------------
# gm_detect_provider — Detect the hosting provider from remote URL or config.
# Prints one of: github, gitlab, gitea, bitbucket, generic
# ---------------------------------------------------------------------------
gm_detect_provider() {
  # If provider.type is explicitly set (not "auto"), return it directly.
  local configured_type
  configured_type="$(gm_config_get 'provider.type' 2>/dev/null || echo "auto")"
  if [[ -n "$configured_type" && "$configured_type" != "auto" ]]; then
    printf '%s' "$configured_type"
    return 0
  fi

  # Determine which remote to inspect.
  local remote_name
  remote_name="$(gm_config_get 'workflow.default_remote' 2>/dev/null || echo "origin")"
  [[ -z "$remote_name" ]] && remote_name="origin"

  local remote_url
  remote_url="$(git remote get-url "$remote_name" 2>/dev/null || true)"
  if [[ -z "$remote_url" ]]; then
    printf 'generic'
    return 0
  fi

  # Extract the hostname from the remote URL.
  local host
  host="$(_gm_extract_host "$remote_url")"

  # Check custom host mapping from config.
  local custom_host
  custom_host="$(gm_config_get 'provider.host' 2>/dev/null || echo "")"
  if [[ -n "$custom_host" ]]; then
    case "$custom_host" in
      # "mygitlab.example.com=gitlab" format.
      *=*)
        local map_host="${custom_host%%=*}"
        local map_provider="${custom_host#*=}"
        if [[ "$host" == "$map_host" ]]; then
          printf '%s' "$map_provider"
          return 0
        fi
        ;;
      # Direct provider name — override for whatever host is detected.
      github|gitlab|gitea|bitbucket)
        printf '%s' "$custom_host"
        return 0
        ;;
    esac
  fi

  # Match well-known hostnames.
  case "$host" in
    github.com|*.github.com)       printf 'github'    ;;
    gitlab.com|*.gitlab.com)       printf 'gitlab'    ;;
    bitbucket.org|*.bitbucket.org) printf 'bitbucket' ;;
    *gitea*|*forgejo*|codeberg.org) printf 'gitea'    ;;
    *)                             printf 'generic'   ;;
  esac

  return 0
}

# ---------------------------------------------------------------------------
# gm_detect_cli — Choose the best available CLI tool.
# Prints: gh, glab, tea, or git
# ---------------------------------------------------------------------------
gm_detect_cli() {
  # Read preference list from config.
  local -a tools
  local prefs
  prefs="$(gm_config_get_array 'provider.cli_preference' 2>/dev/null || true)"

  if [[ -n "$prefs" ]]; then
    while IFS= read -r t; do
      [[ -n "$t" ]] && tools+=("$t")
    done <<< "$prefs"
  fi

  # Default fallback order if config yielded nothing.
  if [[ ${#tools[@]} -eq 0 ]]; then
    tools=(gh glab tea git)
  fi

  local tool
  for tool in "${tools[@]}"; do
    # Trim whitespace.
    tool="${tool#"${tool%%[![:space:]]*}"}"
    tool="${tool%"${tool##*[![:space:]]}"}"
    if command -v "$tool" &>/dev/null; then
      printf '%s' "$tool"
      return 0
    fi
  done

  # git should always exist, but guard anyway.
  printf 'git'
  return 0
}

# ---------------------------------------------------------------------------
# gm_parse_remote_url — Extract OWNER and REPO from a git remote URL.
# Sets GM_REMOTE_OWNER and GM_REMOTE_REPO as global variables.
#
# Supported formats:
#   git@host:owner/repo.git
#   https://host/owner/repo.git
#   ssh://git@host/owner/repo.git
#   ssh://git@host:port/owner/repo.git
#   git@gitlab.com:group/subgroup/repo.git   (nested groups)
# ---------------------------------------------------------------------------
gm_parse_remote_url() {
  local url="${1:-}"

  if [[ -z "$url" ]]; then
    local remote_name
    remote_name="$(gm_config_get 'workflow.default_remote' 2>/dev/null || echo "origin")"
    [[ -z "$remote_name" ]] && remote_name="origin"
    url="$(git remote get-url "$remote_name" 2>/dev/null || true)"
  fi

  if [[ -z "$url" ]]; then
    GM_REMOTE_OWNER=""
    GM_REMOTE_REPO=""
    return 1
  fi

  local path=""

  case "$url" in
    # SSH shorthand: git@host:owner/repo.git
    *@*:*/*)
      path="${url#*:}"
      ;;
    # HTTPS / HTTP / SSH with scheme.
    https://*|http://*|ssh://*)
      path="${url#*://}"       # user@host(:port)/path  or  host/path
      path="${path#*/}"        # strip host portion up to first /
      ;;
    *)
      # Best effort.
      path="${url#*:}"
      [[ "$path" == "$url" ]] && path="${url#*/}"
      ;;
  esac

  # Strip trailing .git and slash.
  path="${path%.git}"
  path="${path%/}"

  # Split: owner = everything before last /, repo = last component.
  if [[ "$path" == */* ]]; then
    GM_REMOTE_REPO="${path##*/}"
    GM_REMOTE_OWNER="${path%/*}"
  else
    GM_REMOTE_REPO="$path"
    GM_REMOTE_OWNER=""
  fi

  export GM_REMOTE_OWNER GM_REMOTE_REPO
  return 0
}

# ---------------------------------------------------------------------------
# _gm_extract_host — Extract hostname from a remote URL.
# ---------------------------------------------------------------------------
_gm_extract_host() {
  local url="$1"
  local host=""

  case "$url" in
    # git@host:owner/repo
    *@*:*/*)
      host="${url#*@}"
      host="${host%%:*}"
      ;;
    https://*|http://*)
      host="${url#*://}"
      host="${host%%/*}"
      host="${host#*@}"       # strip user@ if present
      host="${host%%:*}"      # strip port if present
      ;;
    ssh://*)
      host="${url#ssh://}"
      host="${host#*@}"
      host="${host%%/*}"
      host="${host%%:*}"
      ;;
    *)
      host=""
      ;;
  esac

  printf '%s' "$host"
}

_GM_PROVIDER_DETECT_LOADED=1
