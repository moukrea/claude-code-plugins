#!/usr/bin/env bash
set -euo pipefail

# Post-tool-use hook: provide non-blocking guidance after git operations.
# PostToolUse cannot block — exit code 2 has no effect. All output is advisory.

INPUT=$(cat)

# Fast path: only care about Bash
tool_name=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[[ -n "$command" ]] || exit 0

tool_result=$(printf '%s' "$INPUT" | jq -r '.tool_result // empty')

guidance=""

# ---------------------------------------------------------------------------
# After git merge / pull / rebase with conflicts
# ---------------------------------------------------------------------------
if printf '%s' "$command" | grep -qE '(^|[;&|]\s*)git\s+(merge|pull|rebase)\b'; then
  if printf '%s' "$tool_result" | grep -qi 'CONFLICT'; then
    guidance="Merge conflicts detected. Resolve conflicts in the listed files, then:
- For merge: git add <files> && git commit
- For rebase: git add <files> && git rebase --continue
- To abort: git merge --abort / git rebase --abort
Check conflicted files with: git diff --name-only --diff-filter=U"
  fi
fi

# ---------------------------------------------------------------------------
# After git push rejected
# ---------------------------------------------------------------------------
if printf '%s' "$command" | grep -qE '(^|[;&|]\s*)git\s+push\b'; then
  if printf '%s' "$tool_result" | grep -qiE '(rejected|non-fast-forward)'; then
    guidance="Push was rejected (remote has new commits). Run: git pull --rebase && git push"
  fi
fi

# ---------------------------------------------------------------------------
# After successful git commit — suggest next steps
# ---------------------------------------------------------------------------
if printf '%s' "$command" | grep -qE '(^|[;&|]\s*)git\s+commit\b'; then
  # A successful commit usually contains the branch and short hash in output
  if printf '%s' "$tool_result" | grep -qE '^\[.+\]'; then
    branch=$(git branch --show-current 2>/dev/null || echo "")
    if [[ -n "$branch" ]]; then
      # Check if branch has an upstream
      if git rev-parse --abbrev-ref "${branch}@{upstream}" &>/dev/null; then
        guidance="Commit created. You can push with: git push"
      else
        guidance="Commit created on '${branch}' (no upstream set). Push with: git push -u origin ${branch}"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Emit guidance if any
# ---------------------------------------------------------------------------
if [[ -n "$guidance" ]]; then
  jq -n --arg ctx "[git-master] $guidance" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $ctx
    }
  }'
fi

exit 0
