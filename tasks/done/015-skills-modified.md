# Task 015: Modified Skills — /branch, /finish, /configure

## Status
done

## Dependencies
- 001-config-schema (new config keys referenced by /configure, e.g. `branch.autoStashOnSwitch`, `rebase.autoRebaseBeforePush`, `rebase.allowForcePush`, `worktree.enabled`, `worktree.basePath`)
- 005-rebase-library (drift detection logic used by /finish Step 1.5)

## Spec References
- spec/07-skills-and-claude-md.md

## Scope
Update three existing skill files — `/branch`, `/finish`, and `/configure` — with the v2 additions specified in the spec. The `/branch` skill gains a Step 5 for recording base branch context. The `/finish` skill gains a Step 1.5 for base branch drift detection before push. The `/configure` skill gains 11 new entries in its user-says-to-config-change reference table.

## Acceptance Criteria
- [x] `plugins/git-pilot/skills/branch/SKILL.md` contains a new "Step 5: Record Branch Context" after the existing Step 4, with the exact text from spec section 3.1.
- [x] `plugins/git-pilot/skills/finish/SKILL.md` contains a new "Step 1.5: Check Base Branch Drift" between existing Steps 1 and 2, with the exact text from spec section 3.2.
- [x] `/finish` Step 1.5 documents base branch resolution order: (1) session state `baseBranch` field, (2) `git config branch.${current}.merge` with `refs/heads/` stripped, (3) `git.defaultBranch` from config.
- [x] `plugins/git-pilot/skills/configure/SKILL.md` reference table includes all 11 new entries from spec section 3.4.
- [x] All three SKILL.md files retain valid YAML frontmatter (`name`, `description`).
- [x] Existing steps and content in all three skills are preserved — only additive changes.

## Implementation Notes

### /branch — Add Step 5 (spec section 3.1)

Append after the existing Step 4 (`git switch -c <branch-name>`):

```markdown
## Step 5: Record Branch Context

After creating the branch, note the base branch (the branch you were on before switching)
and the branch purpose (derived from the description). These are used for unrelated work
detection and drift checks.
```

### /finish — Add Step 1.5 (spec section 3.2)

Insert between existing Step 1 ("Check for Uncommitted Changes") and Step 2 ("Push to Remote"):

```markdown
## Step 1.5: Check Base Branch Drift

Before pushing, check if the base branch has advanced:

1. Run `git fetch <remote> <defaultBranch>`.
2. Check for new commits on the base branch since this branch diverged.
3. If the base has new commits and `rebase.autoRebaseBeforePush` is `true`:
   - Attempt `git rebase <remote>/<defaultBranch>`.
   - If rebase succeeds: continue to push.
   - If rebase has conflicts: present conflict details and options to the user.
4. If force push is needed after rebase, follow `rebase.allowForcePush` policy.
```

Base branch determination order (from spec):
1. Session state `baseBranch` field
2. `git config branch.${current}.merge` with `refs/heads/` stripped
3. `git.defaultBranch` from config

### /configure — New Reference Table Entries (spec section 3.4)

Add these rows to the existing table in Step 1:

| User Says | Config Change |
|-----------|--------------|
| "Fetch remote on session start" | `git.autoFetch: true` |
| "Block commits to main" | `git.protectDefaultBranch: "block"` |
| "Don't warn about main branch commits" | `git.protectDefaultBranch: "off"` |
| "Disable unrelated work detection" | `branch.unrelatedWorkDetection: false` |
| "Don't auto-stash on branch switch" | `branch.autoStashOnSwitch: false` |
| "Don't auto-rebase before push" | `rebase.autoRebaseBeforePush: false` |
| "Never force push" | `rebase.allowForcePush: "never"` |
| "Always force push after rebase" | `rebase.allowForcePush: "always"` |
| "Use merge when rebase conflicts" | `rebase.conflictStrategy: "merge-fallback"` |
| "Disable worktrees" | `worktree.enabled: false` |
| "Worktrees in /tmp" | `worktree.basePath: "/tmp/{{project}}-worktrees"` |

## Files to Create or Modify
- plugins/git-pilot/skills/branch/SKILL.md (modify)
- plugins/git-pilot/skills/finish/SKILL.md (modify)
- plugins/git-pilot/skills/configure/SKILL.md (modify)
