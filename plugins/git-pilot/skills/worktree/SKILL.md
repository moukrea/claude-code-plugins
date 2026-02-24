---
name: worktree
description: Manage git worktrees for parallel branch work
---

# /worktree

Manage git worktrees for parallel branch work.

## Step 1: Determine Action

Parse the user's intent:
- `/worktree` or `/worktree list` — list active worktrees
- `/worktree create <branch>` — create a new worktree for a branch
- `/worktree remove <path-or-branch>` — remove a worktree
- `/worktree merge <path-or-branch>` — merge a worktree's branch and clean up

If no argument, show the list of active worktrees.

## Step 2: Execute

### List
1. Read the worktree registry (`.git/git-pilot-worktrees.json`).
2. Also run `git worktree list` for system-level view.
3. Present: path, branch, base branch, creation date, status.

### Create
1. Ask for the branch name (or parse from argument).
2. Ask for the base branch (default: `git.defaultBranch`).
3. Determine the worktree path using `worktree.basePath` config.
4. Run `git worktree add <path> -b <branch> <base>`.
5. Register in the worktree registry.
6. Confirm with the worktree path.

### Remove
1. Identify the worktree by path or branch name.
2. Check for uncommitted changes in the worktree.
3. If uncommitted changes, warn and ask to confirm.
4. Run `git worktree remove <path>`.
5. Optionally delete the branch: `git branch -d <branch>`.
6. Unregister from the registry.

### Merge
1. Identify the worktree by path or branch name.
2. Get the worktree's branch and its base branch from the registry.
3. Switch main worktree to the base branch.
4. Attempt `git merge <worktree-branch> --no-edit`.
5. If conflicts: present them and ask user to resolve.
6. If `worktree.cleanupOnMerge` is `true`: remove the worktree and delete the branch.
7. Confirm the merge.
