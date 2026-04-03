#!/usr/bin/env bash
set -euo pipefail

# Session start hook: load config, detect provider, inject context summary.
# Exits silently (0) if not in a git repo.

# Read hook input (required by the hook protocol even if unused)
cat > /dev/null

# Not in a git repo — nothing to do
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# Load config
# shellcheck source=lib/config.sh
source "${PLUGIN_ROOT}/scripts/lib/config.sh"
gm_config_load

# Detect provider and CLI
# shellcheck source=lib/provider-detect.sh
source "${PLUGIN_ROOT}/scripts/lib/provider-detect.sh"
provider=$(gm_detect_provider)
cli=$(gm_detect_cli)

# Gather context pieces
convention=$(gm_config_get 'commit.convention' || echo "conventional")
max_length=$(gm_config_get 'commit.subject.max_length' || echo "72")
protected_json=$(gm_config_get_json 'branch.protected' 2>/dev/null || echo '[]')
protected=$(printf '%s' "$protected_json" | jq -r 'if type == "array" then join(", ") else . end' 2>/dev/null || echo "main, master")
branch=$(git branch --show-current 2>/dev/null || echo "detached")

# Build summary
summary="[git-master] "
summary+="Provider: ${provider} (cli: ${cli}). "
summary+="Commit convention: ${convention} (max ${max_length} chars). "
summary+="Protected branches: ${protected}. "
summary+="Current branch: ${branch}."

# Output hook response
jq -n --arg ctx "$summary" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
