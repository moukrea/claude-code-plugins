---
name: stash
description: "USE THIS SKILL WHEN the user wants to set aside current work, switch context temporarily, save progress without committing, or needs to switch branches with uncommitted changes. Manages git stashes including save, list, apply, pop, and drop operations. Trigger on 'stash my changes,' 'save this for later,' 'set aside,' 'park this work,' 'switch branches' with dirty working tree, 'come back to this later,' or any need to temporarily shelve uncommitted changes. Even if the user just says 'hold on to this' or 'I need to context-switch,' still use this skill."
user-invocable: true
---

# /stash

Manage git stashes for the current repository.

## Step 1: Determine Action

If the user provided an argument after `/stash`, parse it:
- `/stash` or `/stash save` — stash current changes
- `/stash list` — list all stashes
- `/stash pop` or `/stash apply` — restore the most recent stash
- `/stash drop` — drop the most recent stash

If no argument, ask the user what they want to do.

## Step 2: Execute

### Save
1. Check for uncommitted changes. If none: "Nothing to stash."
2. Ask the user for an optional stash message.
3. Run `git stash push -m "<message>"` (or `git stash push` if no message).
4. Confirm: "Stashed changes: <stash-ref>"

### List
1. Run `git stash list`.
2. If empty: "No stashes found."
3. Present the list with index, branch, and message.

### Pop / Apply
1. Run `git stash list`. If empty: "No stashes to restore."
2. If multiple stashes, show the list and ask which one.
3. For pop: `git stash pop <ref>`. For apply: `git stash apply <ref>`.
4. If conflicts: warn the user and show conflicting files.

### Drop
1. Run `git stash list`. If empty: "No stashes to drop."
2. If multiple stashes, show the list and ask which one.
3. Confirm before dropping.
4. Run `git stash drop <ref>`.
