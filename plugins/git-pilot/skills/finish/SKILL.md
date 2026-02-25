---
name: finish
user-invocable: true
description: "USE THIS SKILL WHEN the user signals that the current unit of work is over. Commits remaining changes, pushes to remote, and optionally creates a merge request to wrap up the session. Trigger on: user says 'done', 'finished', 'that's it', 'ship it', 'wrap it up', 'we're good', 'let's call it', 'I'm done', 'push it', end of session, task completion, or any indication that work is complete. Even if the user only hints at being done or says something casual like 'looks good', still use this skill to ensure nothing is left uncommitted or unpushed."
---

# /finish

Perform the following sequence to finish the current work session.

## Step 1: Check for Uncommitted Changes

Run `git status --porcelain`. If there are any uncommitted changes, commit them following the configured commit format.

## Step 1.5: Check Base Branch Drift

Before pushing, check if the base branch has advanced:

1. Run `git fetch <remote> <defaultBranch>`.
2. Check for new commits on the base branch since this branch diverged.
3. If the base has new commits and `rebase.autoRebaseBeforePush` is `true`:
   - Attempt `git rebase <remote>/<defaultBranch>`.
   - If rebase succeeds: continue to push.
   - If rebase has conflicts: present conflict details and options to the user.
4. If force push is needed after rebase, follow `rebase.allowForcePush` policy.

Base branch is determined in order: (1) session state `baseBranch` field, (2) `git config branch.${current}.merge` with `refs/heads/` stripped, (3) `git.defaultBranch` from config.

## Step 2: Push to Remote

Follow the push workflow:

1. Check if a remote exists.
2. Check for unpushed commits: run `git log @{u}..HEAD --oneline 2>/dev/null`.
3. Based on `remote.pushOnFinish` (or `remote.autoPush`):
   - If `true`, push automatically.
   - If `false` or not set, ask the user whether they want to push.
4. Push using: `git push -u <remote.defaultName> <branch>`

## Step 3: Create MR/PR

Follow the merge request creation workflow:

1. Check `mergeRequest.enabled` and `mergeRequest.createOnFinish`. If both are not `true`, skip this step.
2. Detect the platform:
   - If `mergeRequest.platform` is `"auto"`, inspect the remote URL for `github.com` or `gitlab` to determine the platform.
   - Verify the required CLI tool is available (`gh` for GitHub, `glab` for GitLab).
3. Build the title:
   - If `mergeRequest.titleFromBranch` is `true`, derive the title from the branch name.
   - Otherwise, use the last commit subject.
4. Build the body:
   - If `mergeRequest.bodyTemplate` is set, use it.
   - Otherwise, generate a default body with Summary, Commits, and Files Changed sections.
5. Apply configured flags:
   - `--draft` if `mergeRequest.draft` is `true`
   - `--label` for each label in `mergeRequest.labels`
   - `--assignee @me` if `mergeRequest.assignToSelf` is `true`
   - `--base <defaultBranch>` using `git.defaultBranch`
6. Create the MR/PR:
   - For GitHub: `gh pr create --title "..." --body "..." [flags]`
   - For GitLab: `glab mr create --title "..." --description "..." [flags]`

## Step 4: Show Summary

Optionally generate and display a work summary using the same logic as the `/summary` skill.
