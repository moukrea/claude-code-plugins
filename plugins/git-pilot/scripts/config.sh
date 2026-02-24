#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

load_config() {
  local cwd="${1:-.}"
  local defaults="$PLUGIN_ROOT/defaults/config.json"
  local global="$HOME/.claude/git-pilot.json"
  local local_cfg="$cwd/.claude/git-pilot.json"

  local result
  result=$(cat "$defaults")

  if [[ -f "$global" ]]; then
    result=$(echo "$result" | jq -s '.[0] * .[1]' - "$global" 2>/dev/null || echo "$result")
  fi

  if [[ -f "$local_cfg" ]]; then
    result=$(echo "$result" | jq -s '.[0] * .[1]' - "$local_cfg" 2>/dev/null || echo "$result")
  fi

  echo "$result"
}

get_config() {
  local config="$1"
  local key="$2"
  local default="$3"
  echo "$config" | jq -r "if ($key) == null then \"$default\" else ($key) end"
}

normalize_protect_default_branch() {
  local value="$1"
  case "$value" in
    true)  echo "warn" ;;
    false) echo "off" ;;
    warn|block|off) echo "$value" ;;
    *) echo "warn" ;;
  esac
}
