---
name: rebase
description: "USE THIS SKILL WHEN the user mentions rebasing, the current branch is behind the base branch, before pushing on long-lived feature branches, or when merge conflicts from diverged history need resolution. Rebases the current branch onto a target branch with conflict handling and force-push management. Trigger on 'rebase,' 'update my branch,' 'catch up with main,' 'branch is behind,' 'linearize history,' 'clean up commits before push,' or any signal that the branch needs to incorporate upstream changes. Even if the user just says 'sync with main' or 'get latest changes,' still use this skill."
user-invocable: true
---

# /rebase

Rebase the current branch onto a target branch.

## Step 1: Determine Target

If the user specified a target branch (e.g., `/rebase main`), use it.
Otherwise, default to the configured `git.defaultBranch`.

## Step 2: Pre-flight Checks

1. Ensure the working tree is clean. If uncommitted changes exist, ask to stash or commit first.
2. Fetch the remote target branch: `git fetch <remote> <target>`.
3. Check how many commits will be rebased: `git rev-list --count <remote>/<target>..HEAD`.
4. Show the user: "Rebasing N commit(s) onto <remote>/<target>."

## Step 3: Execute Rebase

1. Run `git rebase <remote>/<target>`.
2. If success: "Rebase completed successfully."
3. If conflicts:
   - Show conflicting files and conflict details.
   - Present resolution options:
     a. Resolve manually (edit files, then `git add <file>` and `git rebase --continue`)
     b. Accept theirs for all (`git checkout --theirs . && git add .`)
     c. Accept ours for all (`git checkout --ours . && git add .`)
     d. Abort (`git rebase --abort`)
   - After resolution, run `git rebase --continue`.

## Step 4: Handle Force Push

If the branch was previously pushed and rebase rewrote history:
1. Inform: "Rebase rewrote history. Force push is needed to update the remote."
2. Based on `rebase.allowForcePush`:
   - `"ask"`: Ask user to confirm force push.
   - `"always"`: Push with `--force-with-lease` automatically.
   - `"never"`: Inform that force push is disabled.
3. Use `git push --force-with-lease <remote> <branch>`.
