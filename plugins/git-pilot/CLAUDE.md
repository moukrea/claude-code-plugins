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
