#!/usr/bin/env bash
# provider-dispatch.sh — Unified dispatch layer for all provider operations.
# Meant to be sourced, not executed directly.

# Guard against double-sourcing.
[[ -n "${_GM_PROVIDER_DISPATCH_LOADED:-}" ]] && return 0

# Exit codes:
#   0 = success
#   1 = error
#   2 = operation not supported by this provider
#   3 = authentication required

# All valid operations.
readonly _GM_VALID_OPERATIONS="pr-create pr-list pr-view pr-diff pr-merge pr-close pr-comment pr-review pr-checks pr-labels pr-reviewers ci-status ci-logs ci-retry repo-info"

# Main dispatch entry point.
# Usage: gm_provider <operation> [args...]
gm_provider() {
  local operation="${1:-}"
  if [[ -z "$operation" ]]; then
    echo '{"error":"no operation specified"}' >&2
    return 1
  fi
  shift

  # Validate operation name.
  if ! _gm_valid_operation "$operation"; then
    echo "{\"error\":\"unknown operation: $operation\"}" >&2
    return 1
  fi

  # Determine provider if not already set.
  if [[ -z "${GIT_MASTER_PROVIDER:-}" ]]; then
    GIT_MASTER_PROVIDER="$(gm_detect_provider)"
    export GIT_MASTER_PROVIDER
  fi

  # Build the provider fallback chain.
  local -a chain
  chain=("$GIT_MASTER_PROVIDER")

  local fallback_enabled
  fallback_enabled="$(gm_config_get 'provider.fallback_enabled' 2>/dev/null || echo "true")"

  if [[ "$fallback_enabled" == "true" ]]; then
    # Add generic as the last resort if not already the provider.
    if [[ "$GIT_MASTER_PROVIDER" != "generic" ]]; then
      chain+=("generic")
    fi
  fi

  local provider rc
  for provider in "${chain[@]}"; do
    _gm_source_provider "$provider" || continue

    # Convert operation to function name: pr-create -> _<provider>_pr_create
    local func_name
    func_name="_${provider}_$(echo "$operation" | tr '-' '_')"

    if ! declare -f "$func_name" &>/dev/null; then
      # Function not defined in this provider; try next.
      continue
    fi

    rc=0
    "$func_name" "$@" || rc=$?

    case $rc in
      0)
        return 0
        ;;
      2)
        # Not supported; try next in chain.
        continue
        ;;
      3)
        # Auth required — propagate immediately, don't fall back.
        return 3
        ;;
      *)
        # Error — if fallback is enabled, try next; otherwise propagate.
        if [[ "$fallback_enabled" == "true" ]]; then
          echo "{\"warning\":\"$provider failed for $operation, trying fallback\"}" >&2
          continue
        fi
        return "$rc"
        ;;
    esac
  done

  # Nothing succeeded.
  echo "{\"error\":\"operation '$operation' not supported by any available provider\"}" >&2
  return 2
}

# --- Internal helpers ---

# Check if an operation name is valid.
_gm_valid_operation() {
  local op="$1"
  local valid
  for valid in $_GM_VALID_OPERATIONS; do
    if [[ "$valid" == "$op" ]]; then
      return 0
    fi
  done
  return 1
}

# Source a provider script if not already loaded.
# Tracks loaded providers in _GM_LOADED_PROVIDERS to avoid re-sourcing.
declare -g -A _GM_LOADED_PROVIDERS 2>/dev/null || true

_gm_source_provider() {
  local provider="$1"

  # Skip if already loaded.
  if [[ "${_GM_LOADED_PROVIDERS[$provider]:-}" == "1" ]]; then
    return 0
  fi

  # Locate the provider script relative to this file.
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local provider_file="$script_dir/provider-${provider}.sh"

  if [[ ! -f "$provider_file" ]]; then
    echo "{\"error\":\"provider script not found: $provider_file\"}" >&2
    return 1
  fi

  # shellcheck source=/dev/null
  source "$provider_file"
  _GM_LOADED_PROVIDERS[$provider]="1"
  return 0
}

_GM_PROVIDER_DISPATCH_LOADED=1
