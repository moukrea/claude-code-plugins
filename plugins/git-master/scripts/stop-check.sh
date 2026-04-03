#!/usr/bin/env bash
set -euo pipefail

# Stop hook: warn about pending git state before Claude stops.
# Outputs {"decision": "block", "reason": "..."} or {"decision": "approve"}.

INPUT=$(cat)

# Prevent infinite loop — if stop_hook_active is set, approve immediately
stop_hook_active=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')
if [[ "$stop_hook_active" == "true" ]]; then
  exit 0
fi

# Not in a git repo — nothing to check
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  jq -n '{"decision": "approve"}'
  exit 0
fi

warnings=()

# Check for staged uncommitted files
staged_count=$(git diff --cached --name-only 2>/dev/null | wc -l)
if (( staged_count > 0 )); then
  warnings+=("${staged_count} staged file(s) not yet committed")
fi

# Check for unresolved merge conflicts
conflict_count=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)
if (( conflict_count > 0 )); then
  warnings+=("${conflict_count} file(s) with unresolved merge conflicts")
fi

# Check for active rebase
git_dir=$(git rev-parse --git-dir 2>/dev/null)
if [[ -d "${git_dir}/rebase-merge" || -d "${git_dir}/rebase-apply" ]]; then
  warnings+=("a rebase is in progress")
fi

# Check for active merge
if [[ -f "${git_dir}/MERGE_HEAD" ]]; then
  warnings+=("a merge is in progress")
fi

# Emit decision
if (( ${#warnings[@]} > 0 )); then
  reason="[git-master] Pending git state — please resolve before stopping: $(IFS='; '; echo "${warnings[*]}")."
  jq -n --arg r "$reason" '{"decision": "block", "reason": $r}'
else
  jq -n '{"decision": "approve"}'
fi

exit 0
