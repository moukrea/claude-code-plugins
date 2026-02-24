# Task 014: Hook Registration (hooks.json Update)

## Status
done

## Dependencies
- 013-hook-prompt-context (registers the new `prompt-context.sh` script; should come after the script exists)

## Spec References
- spec/06-hooks-and-lifecycle.md (section 1)

## Scope
Update `hooks/hooks.json` to register the new `UserPromptSubmit` hook entry for `prompt-context.sh` and adjust timeouts for existing hooks to accommodate new v2 functionality (fetch, rebase, drift detection).

## Acceptance Criteria
- [x] `SessionStart` timeout changed from `15` to `30` (fetch + freshness checks added)
- [x] `PostToolUse` Bash matcher timeout changed from `10` to `15` (push rejection + rebase handling)
- [x] `Stop` timeout changed from `30` to `45` (drift detection + rebase + worktree cleanup)
- [x] New `UserPromptSubmit` entry added with `prompt-context.sh` command and timeout `5`
- [x] `UserPromptSubmit` entry has no `matcher` field (runs on all user prompts)
- [x] All existing hook entries (SessionStart, PreToolUse, PostToolUse Write|Edit, PostToolUse Bash, Stop) are preserved with no other changes
- [x] The resulting JSON is valid and parseable

## Implementation Notes

### Target `hooks.json` content

The v1 file is at `plugins/git-pilot/hooks/hooks.json`. Replace with:

```json
{
  "description": "git-pilot: Automated git workflow management",
  "hooks": {
    "SessionStart": [{
      "matcher": "startup",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh",
        "timeout": 30
      }]
    }],
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/prompt-context.sh",
        "timeout": 5
      }]
    }],
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/pre-commit.sh",
        "timeout": 10
      }]
    }],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/post-write.sh",
          "timeout": 10
        }]
      },
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/post-bash.sh",
          "timeout": 15
        }]
      }
    ],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/session-stop.sh",
        "timeout": 45
      }]
    }]
  }
}
```

### Changes from v1

| Hook | Field | v1 | v2 | Reason |
|------|-------|----|----|--------|
| SessionStart | timeout | 15 | 30 | fetch + freshness check |
| PostToolUse (Bash) | timeout | 10 | 15 | push rejection + rebase |
| Stop | timeout | 30 | 45 | drift + rebase + MR + worktree cleanup |
| UserPromptSubmit | (new) | -- | 5 | branch context for unrelated work detection |

The `PreToolUse` timeout remains at `10` (no change). The `PostToolUse` Write|Edit timeout remains at `10` (no change).

Note: `UserPromptSubmit` has no `matcher` field because it runs on every user prompt submission.

## Files to Create or Modify
- plugins/git-pilot/hooks/hooks.json (modify -- update timeouts, add UserPromptSubmit entry)
