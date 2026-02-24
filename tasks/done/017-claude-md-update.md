# Task 017: CLAUDE.md Update — All 10 Rules and Updated Skill Reference

## Status
done

## Dependencies
- 004-agent-library (CLAUDE.md Rule 10 references agent teams detection and behavior)
- 005-rebase-library (CLAUDE.md Rule 9 references conflict resolution from rebase operations)
- 006-worktree-library (CLAUDE.md Rule 10 references worktree operations for agents)
- 007-stash-functions (CLAUDE.md Rule 8 references auto-stash on branch switch)

## Spec References
- spec/07-skills-and-claude-md.md

## Scope
Replace the existing v1 CLAUDE.md (6 rules, 4 skills in reference table) with the complete v2 version containing all 10 rules and 7 skills in the reference table. The v2 CLAUDE.md adds Rule 7 (unrelated work detection), Rule 8 (branch switching with auto-stash), Rule 9 (conflict resolution guidance), and Rule 10 (agent teams behavior). The skill reference table adds `/stash`, `/worktree`, and `/rebase`.

## Acceptance Criteria
- [x] `plugins/git-pilot/CLAUDE.md` contains exactly 10 numbered rules, each with the exact text from spec section 1.
- [x] Rule 7 (Unrelated Work Detection) includes all 5 sub-points: branch name parsing, recent commits review, assessment with the exact prompt text, "when NOT to prompt" conditions, and branch switch reference.
- [x] Rule 8 (Branch switching) includes all 3 steps: auto-stash when `branch.autoStashOnSwitch` is `true`, auto-restore on target branch, conflict warning on restore failure.
- [x] Rule 9 (Conflict resolution) includes all 4 steps: read conflicting files, provide recommendations (one-side vs both-side vs deleted), present options (resolve manually / accept ours / accept theirs / abort), continue after resolution.
- [x] Rule 10 (Agent Teams) includes all 4 points: no push/MR/branch-switch prompts, commit rules still active, no auto-commit suggestions, stay in worktree directory.
- [x] Skill reference table lists all 7 skills: `/branch`, `/finish`, `/summary`, `/configure`, `/stash`, `/worktree`, `/rebase` with correct "When to use" descriptions.

## Implementation Notes

Replace the entire content of `plugins/git-pilot/CLAUDE.md` with the complete v2 version from spec section 1. The exact content is provided in the spec between the opening and closing markdown code fence.

### Rules 1-6

Rules 1 through 6 are unchanged from v1. They must be preserved exactly. Verify no unintended drift.

### Rule 7: Unrelated Work Detection

```markdown
## Rule 7: Unrelated work detection

Before starting work on a new user request, assess whether the request is related
to the current branch's purpose:

1. **Branch name**: Parse the branch name for semantic meaning. For example,
   `feat/add-dark-mode` implies work on dark mode; `fix/login-timeout` implies
   fixing a login timeout bug.
2. **Recent commits**: Review the commit log on this branch for scope context.
3. **Assessment**: If the user's request is clearly unrelated to the branch's
   purpose (different feature, different bug, different module), prompt the user:

   "This work appears unrelated to the current branch (`<branch-name>`).
   Options:
   1. Create a new branch from `<default-branch>` (recommended — keeps branches focused)
   2. Create a new branch from the current branch (if this work depends on current changes)
   3. Continue on this branch"

4. **When NOT to prompt**: Do not prompt for closely related work (e.g., fixing
   a bug discovered while implementing a feature on the same branch), for work
   on the default branch, or for branches with no commits yet.
5. **If the user chooses to create a new branch**: Follow the branch switch
   workflow (see Rule 8).
```

### Rule 8: Branch switching

```markdown
## Rule 8: Branch switching

When switching branches (via /branch, user request, or unrelated work detection):

1. If there are uncommitted changes and `branch.autoStashOnSwitch` is `true`, stash
   them automatically before switching. Inform the user: "Stashed changes on '<branch>'."
2. After switching, check if there's a git-pilot stash for the target branch and
   restore it automatically.
3. If stash restoration fails (conflicts), inform the user and suggest manual resolution.
```

### Rule 9: Conflict resolution

```markdown
## Rule 9: Conflict resolution

When a rebase or merge results in conflicts:

1. Read the conflicting files to understand the nature of each conflict.
2. For each conflict, provide a recommendation:
   - If only one side modified the region, recommend accepting that side.
   - If both sides modified the same lines, recommend manual review.
   - If a file was deleted on one side, explain the tradeoff.
3. Present clear options: resolve manually, accept ours, accept theirs, abort.
4. After the user resolves conflicts, continue the interrupted operation
   (`git rebase --continue` or `git merge --continue`).
```

### Rule 10: Agent Teams

```markdown
## Rule 10: Agent Teams

When operating as a spawned agent (not the orchestrator):

1. Do not prompt for push, MR creation, or branch switching. These are
   orchestrator-only operations.
2. Follow commit rules normally — agents must still use proper commit format.
3. Do not run auto-commit suggestions. Commit when instructed by the orchestrator.
4. If instructed to work in a specific worktree directory, stay in that directory.
```

### Updated Skill Reference Table

```markdown
## Skill reference

| Skill | When to use |
|-------|-------------|
| `/branch` | Proactively when on the default branch before making changes |
| `/finish` | When the user says they're done, or at session end |
| `/summary` | When the user asks for a recap of branch work |
| `/configure` | When the user wants to change git-pilot settings |
| `/stash` | When the user wants to manage git stashes |
| `/worktree` | When the user wants to manage git worktrees |
| `/rebase` | When the user wants to rebase the current branch |
```

## Files to Create or Modify
- plugins/git-pilot/CLAUDE.md (modify)
