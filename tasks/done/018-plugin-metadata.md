# Task 018: Plugin Metadata — Version Bump to 2.0.0

## Status
done

## Dependencies
- 017-claude-md-update (CLAUDE.md must be finalized before bumping the version that ships with it)

## Spec References
- spec/07-skills-and-claude-md.md

## Scope
Update `plugin.json` to reflect the v2.0.0 release: bump the version number from `"1.1.0"` to `"2.0.0"` and update the description to reflect all new v2 capabilities. This is a major version bump because v2 adds new behavioral rules, new skills, new library scripts, and new config keys that change the plugin's behavior.

## Acceptance Criteria
- [x] `plugins/git-pilot/.claude-plugin/plugin.json` has `"version": "2.0.0"`.
- [x] The `"description"` field is updated to reflect v2 capabilities (rebase, worktrees, stash, agent teams, conflict resolution, unrelated work detection).
- [x] The `"keywords"` array includes new v2-relevant keywords (at minimum: `"rebase"`, `"worktree"`, `"stash"`, `"agent-teams"`).
- [x] The file remains valid JSON (`jq . plugin.json` succeeds).
- [x] Existing fields (`name`, `author`, `license`, `hooks`, `skills`) are preserved unchanged.

## Implementation Notes

### Current plugin.json

```json
{
  "name": "git-pilot",
  "version": "1.1.0",
  "description": "Automated git workflow management for Claude Code — branch creation, commit formatting, push/MR workflows, and natural language configuration",
  "author": {
    "name": "git-pilot contributors"
  },
  "license": "MIT",
  "keywords": [
    "git",
    "workflow",
    "commits",
    "branches",
    "merge-request",
    "pull-request",
    "conventional-commits"
  ],
  "hooks": "./hooks/hooks.json",
  "skills": "./skills/"
}
```

### Changes

1. `"version"`: `"1.1.0"` -> `"2.0.0"`
2. `"description"`: Update to mention the new v2 features. Suggested: `"Automated git workflow management for Claude Code — branch creation, commit formatting, push/MR workflows, rebase and conflict resolution, worktree management, stash automation, agent teams support, and natural language configuration"`
3. `"keywords"`: Add `"rebase"`, `"worktree"`, `"stash"`, `"agent-teams"`, `"conflict-resolution"` to the existing array.

### Validation

After writing, verify with:

```bash
jq . plugins/git-pilot/.claude-plugin/plugin.json
```

## Files to Create or Modify
- plugins/git-pilot/.claude-plugin/plugin.json (modify)
