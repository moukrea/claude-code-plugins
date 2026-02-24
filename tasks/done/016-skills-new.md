# Task 016: New Skills — /stash, /worktree, /rebase

## Status
done

## Dependencies
- 005-rebase-library (rebase.sh functions invoked by /rebase skill: `attempt_rebase()`, `get_conflict_details()`, `needs_force_push()`)
- 006-worktree-library (worktree.sh functions invoked by /worktree skill: `create_worktree()`, `remove_worktree()`, `list_worktrees()`, `merge_worktree_branch()`)
- 007-stash-functions (`auto_stash()`, `auto_restore_stash()`, `has_uncommitted_changes()` invoked by /stash skill)

## Spec References
- spec/07-skills-and-claude-md.md

## Scope
Create three new skill directories and SKILL.md files: `/stash` for managing git stashes, `/worktree` for managing git worktrees for parallel branch work, and `/rebase` for rebasing the current branch onto a target. Each skill file uses the standard YAML frontmatter format and provides step-by-step workflows for the Claude agent.

## Acceptance Criteria
- [x] `plugins/git-pilot/skills/stash/SKILL.md` exists with valid frontmatter (`name: stash`, `description: Manage git stashes - save, list, apply, or drop`) and complete workflow matching spec section 4.1.
- [x] `plugins/git-pilot/skills/worktree/SKILL.md` exists with valid frontmatter (`name: worktree`, `description: Manage git worktrees for parallel branch work`) and complete workflow matching spec section 4.2.
- [x] `plugins/git-pilot/skills/rebase/SKILL.md` exists with valid frontmatter (`name: rebase`, `description: Rebase current branch onto another branch`) and complete workflow matching spec section 4.3.
- [x] `/stash` skill covers all four actions: save, list, pop/apply, drop — each with the exact sub-steps from the spec.
- [x] `/worktree` skill covers all four actions: list, create, remove, merge — each with the exact sub-steps from the spec.
- [x] `/rebase` skill covers all four steps: determine target, pre-flight checks, execute rebase, handle force push — with the exact details from the spec.

## Implementation Notes

### SKILL.md Frontmatter Format

All skill files must begin with YAML frontmatter:

```yaml
---
name: <skill-name>
description: <one-line description>
---
```

### /stash — spec section 4.1

Create `plugins/git-pilot/skills/stash/SKILL.md` with the following content verbatim from the spec:

- **Frontmatter**: `name: stash`, `description: Manage git stashes - save, list, apply, or drop`
- **Step 1: Determine Action** — Parse argument: `/stash` or `/stash save` (stash current changes), `/stash list` (list all), `/stash pop` or `/stash apply` (restore most recent), `/stash drop` (drop most recent). If no argument, ask the user.
- **Step 2: Execute** — Four sub-sections:
  - **Save**: Check for uncommitted changes. Ask for optional message. Run `git stash push -m "<message>"`. Confirm with stash ref.
  - **List**: Run `git stash list`. If empty: "No stashes found." Present index, branch, message.
  - **Pop / Apply**: Run `git stash list`. If empty: "No stashes to restore." If multiple, show list and ask which one. For pop: `git stash pop <ref>`. For apply: `git stash apply <ref>`. If conflicts: warn and show conflicting files.
  - **Drop**: Run `git stash list`. If empty: "No stashes to drop." If multiple, show list and ask. Confirm before dropping. Run `git stash drop <ref>`.

### /worktree — spec section 4.2

Create `plugins/git-pilot/skills/worktree/SKILL.md` with the following content verbatim from the spec:

- **Frontmatter**: `name: worktree`, `description: Manage git worktrees for parallel branch work`
- **Step 1: Determine Action** — Parse: `/worktree` or `/worktree list` (list), `/worktree create <branch>` (create), `/worktree remove <path-or-branch>` (remove), `/worktree merge <path-or-branch>` (merge). Default to list if no argument.
- **Step 2: Execute** — Four sub-sections:
  - **List**: Read `.git/git-pilot-worktrees.json` registry. Also run `git worktree list`. Present path, branch, base branch, creation date, status.
  - **Create**: Ask/parse branch name. Ask base branch (default: `git.defaultBranch`). Determine path via `worktree.basePath`. Run `git worktree add <path> -b <branch> <base>`. Register in registry. Confirm with path.
  - **Remove**: Identify by path or branch. Check for uncommitted changes. If uncommitted, warn and confirm. Run `git worktree remove <path>`. Optionally `git branch -d <branch>`. Unregister from registry.
  - **Merge**: Identify by path or branch. Get branch and base from registry. Switch main worktree to base. Attempt `git merge <worktree-branch> --no-edit`. If conflicts: present and ask to resolve. If `worktree.cleanupOnMerge` is `true`: remove worktree and delete branch. Confirm.

### /rebase — spec section 4.3

Create `plugins/git-pilot/skills/rebase/SKILL.md` with the following content verbatim from the spec:

- **Frontmatter**: `name: rebase`, `description: Rebase current branch onto another branch`
- **Step 1: Determine Target** — If user specified target (e.g., `/rebase main`), use it. Otherwise default to `git.defaultBranch`.
- **Step 2: Pre-flight Checks** — Ensure clean working tree (ask to stash/commit if dirty). Fetch remote: `git fetch <remote> <target>`. Count commits: `git rev-list --count <remote>/<target>..HEAD`. Show: "Rebasing N commit(s) onto <remote>/<target>."
- **Step 3: Execute Rebase** — Run `git rebase <remote>/<target>`. On success: "Rebase completed successfully." On conflicts: show conflicting files and details, present options (resolve manually, accept theirs `git checkout --theirs . && git add .`, accept ours `git checkout --ours . && git add .`, abort `git rebase --abort`). After resolution: `git rebase --continue`.
- **Step 4: Handle Force Push** — If branch was previously pushed and rebase rewrote history: inform "Rebase rewrote history. Force push is needed to update the remote." Based on `rebase.allowForcePush`: `"ask"` prompts user, `"always"` auto-pushes with `--force-with-lease`, `"never"` informs force push is disabled. Use `git push --force-with-lease <remote> <branch>`.

## Files to Create or Modify
- plugins/git-pilot/skills/stash/SKILL.md (new)
- plugins/git-pilot/skills/worktree/SKILL.md (new)
- plugins/git-pilot/skills/rebase/SKILL.md (new)
