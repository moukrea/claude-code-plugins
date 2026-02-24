# Module 07: Skills and CLAUDE.md

## Cross-references

- **`01-config-and-state.md`** — `load_config`, `get_config`, session state schema, `get_state_file`, `read_state`, `update_state`, `init_state`, `write_state`.
- **`03-rebase-and-conflicts.md`** — `attempt_rebase()`, `get_conflict_details()`, `needs_force_push()`, `get_base_branch_drift()` used by `/rebase` and `/finish`.
- **`04-agent-and-worktree.md`** — `create_worktree()`, `remove_worktree()`, `register_worktree()`, `unregister_worktree()`, `list_worktrees()`, `merge_worktree_branch()` used by `/worktree`.
- **`05-stash-and-robustness.md`** — `auto_stash()`, `auto_restore_stash()`, `has_uncommitted_changes()` used by `/stash` and Rule 8.

## 1. Complete v2 CLAUDE.md

Replaces the v1 version. Contains 10 rules and an updated skill reference table.

### File: `plugins/git-pilot/CLAUDE.md`

```markdown
# git-pilot — Git Workflow Autopilot

git-pilot manages the full git workflow lifecycle. You MUST follow these rules throughout every session.

## Rule 1: Always act on hook messages

When you receive a system message prefixed with `[git-pilot]` from any hook (SessionStart, PostToolUse, Stop), you MUST act on it using AskUserQuestion BEFORE continuing with other work. Never ignore these messages. Present clear, concise options relevant to the prompt.

## Rule 2: Branch discipline

- Never work directly on the default branch. If you're on the default branch when starting work, follow the `/branch` skill workflow to create a feature branch before making any changes.
- Name branches using the configured pattern (default: `{{type}}/{{description}}`, kebab-case).
- Available types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `perf`, `build`, `ci`.
- If the user's request clearly implies a branch type and description, you can infer the branch name and propose it. Otherwise, ask.
- Check `.claude/git-pilot.json` (local) or `~/.claude/git-pilot.json` (global) for project-specific overrides.

## Rule 3: Commit discipline

- Follow the configured commit format (default: `{{type}}({{scope}}): {{description}}`).
- Do NOT include `Co-Authored-By`, `Generated with`, or any AI attribution lines in commits.
- Keep commit subjects under the configured max length (default: 72).
- Use imperative mood ("add" not "added").
- One logical change per commit. When you've completed a coherent unit of work, commit it — don't accumulate unrelated changes.
- **Body policy**: Check `commit.body.required` in the effective config (defaults, global, local merged). If `false`, commits MUST be subject-line only — do NOT include a body. The only exception is breaking changes: when the subject contains `!:` and `commit.breakingChange.requireBody` is `true`, a body starting with the configured `bodyPrefix` (default: `BREAKING CHANGE: `) is required.

## Rule 4: Push workflow

After every successful `git commit`, check for unpushed commits. If there are any and a remote exists:
- Use AskUserQuestion to prompt the user with two options: **"Push to <remote>/<branch>"** and **"Skip"**.
- If they choose to push, run: `git push -u <remote> <branch>`.
- Do NOT silently skip this step or just mention it in passing. The user expects an interactive prompt.

## Rule 5: Session end

When finishing a session, follow the `/finish` skill workflow:
1. Commit any remaining uncommitted changes.
2. If unpushed commits exist, prompt to push (same as Rule 4).
3. If merge request creation is enabled, offer to create one using the appropriate platform CLI (`gh` for GitHub, `glab` for GitLab) or skip silently if the CLI isn't available.

## Rule 6: Configuration

- Users can change git-pilot settings by asking in natural language (via `/configure` skill).
- Global config: `~/.claude/git-pilot.json`
- Local config: `.claude/git-pilot.json`
- Local settings override global settings which override plugin defaults.
- When changing config, ask whether the change should be global or project-specific.

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

## Rule 8: Branch switching

When switching branches (via /branch, user request, or unrelated work detection):

1. If there are uncommitted changes and `branch.autoStashOnSwitch` is `true`, stash
   them automatically before switching. Inform the user: "Stashed changes on '<branch>'."
2. After switching, check if there's a git-pilot stash for the target branch and
   restore it automatically.
3. If stash restoration fails (conflicts), inform the user and suggest manual resolution.

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

## Rule 10: Agent Teams

When operating as a spawned agent (not the orchestrator):

1. Do not prompt for push, MR creation, or branch switching. These are
   orchestrator-only operations.
2. Follow commit rules normally — agents must still use proper commit format.
3. Do not run auto-commit suggestions. Commit when instructed by the orchestrator.
4. If instructed to work in a specific worktree directory, stay in that directory.

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

## 2. Unrelated Work Detection

**Mechanism**: CLAUDE.md Rule 7 + session state context. No additional hook beyond `prompt-context.sh` (provides branch context on every user prompt).

**Preconditions**: On a feature branch (not default branch). `branch.unrelatedWorkDetection` is `true`. Branch has at least one commit.

### 2.1 Branch Purpose Derivation

Stored in session state field `branchPurpose` at init.

```bash
# In git-utils.sh
derive_branch_purpose() {
  local branch_name="$1"

  # Strip type prefix (e.g., "feat/", "fix/")
  local description
  description=$(echo "$branch_name" | sed 's|^[^/]*/||')

  # Convert kebab-case/snake_case to words
  description=$(echo "$description" | tr '-' ' ' | tr '_' ' ')

  echo "$description"
}
```

`session-start.sh` stores `branchPurpose` in state and includes it in its systemMessage for session-wide context. The extended state init in `session-start.sh`:

```bash
if [[ -n "$SESSION_ID" ]]; then
  base_branch="$default_branch"
  branch_purpose=""
  if [[ -n "$current_branch" ]] && [[ "$current_branch" != "$default_branch" ]]; then
    branch_purpose=$(derive_branch_purpose "$current_branch")
    # Try to detect base branch from tracking config
    configured_base=$(git config "branch.${current_branch}.merge" 2>/dev/null | sed 's|refs/heads/||' || true)
    if [[ -n "$configured_base" ]]; then
      base_branch="$configured_base"
    fi
  fi
  init_state "$SESSION_ID" "$current_branch" "$previous_branch" "$base_branch" "$branch_purpose"
fi
```

## 3. Modifications to Existing Skills

### 3.1 `/branch` — Base Branch Recording (add after existing Step 4)

```markdown
## Step 5: Record Branch Context

After creating the branch, note the base branch (the branch you were on before switching)
and the branch purpose (derived from the description). These are used for unrelated work
detection and drift checks.
```

### 3.2 `/finish` — Drift Detection (add between existing Step 1 and Step 2)

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

The `/finish` skill calls the same drift detection logic as `session-stop.sh`. Base branch determined in order: (1) session state `baseBranch` field, (2) `git config branch.${current}.merge` with `refs/heads/` stripped, (3) `git.defaultBranch` from config.

### 3.3 `/summary` — No modifications needed for v2

The `/summary` skill requires no modifications for v2. It continues to work as-is, reading session state and commit history to produce a branch work recap.

### 3.4 `/configure` — New Config Keys (add to reference table)

```markdown
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
```

## 4. New Skills

### 4.1 `/stash` — File: `plugins/git-pilot/skills/stash/SKILL.md`

```markdown
---
name: stash
description: Manage git stashes - save, list, apply, or drop
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
```

### 4.2 `/worktree` — File: `plugins/git-pilot/skills/worktree/SKILL.md`

```markdown
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
```

### 4.3 `/rebase` — File: `plugins/git-pilot/skills/rebase/SKILL.md`

```markdown
---
name: rebase
description: Rebase current branch onto another branch
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
```

## 5. Config Keys Reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `branch.unrelatedWorkDetection` | boolean | `true` | Enable unrelated work detection (Rule 7) |
| `branch.autoStashOnSwitch` | boolean | `true` | Auto-stash on branch switch (Rule 8) |
| `rebase.autoRebaseBeforePush` | boolean | `true` | Rebase onto base before push (`/finish`) |
| `rebase.conflictStrategy` | string | `"prompt"` | `"prompt"` / `"abort"` / `"merge-fallback"` |
| `rebase.allowForcePush` | string | `"ask"` | `"ask"` / `"never"` / `"always"` |
| `worktree.enabled` | boolean | `true` | Enable worktree management (`/worktree`) |
| `worktree.basePath` | string | `"../{{project}}-worktrees"` | Worktree directory pattern |
| `worktree.cleanupOnMerge` | boolean | `true` | Remove worktree after merge |
| `git.protectDefaultBranch` | string | `"warn"` | `"warn"` / `"block"` / `"off"` |
| `agentTeams.suppressPromptsForAgents` | boolean | `true` | Suppress interactive prompts for spawned agents (see `04-agent-and-worktree.md`) |
| `agentTeams.orchestratorOnly` | array | `["push", "mr"]` | Operations restricted to orchestrator agent (see `04-agent-and-worktree.md`) |
