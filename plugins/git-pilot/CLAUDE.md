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
- Use AskUserQuestion to prompt the user with two options: **"Push to \<remote\>/\<branch\>"** and **"Skip"**.
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

## Skill reference

| Skill | When to use |
|-------|-------------|
| `/branch` | Proactively when on the default branch before making changes |
| `/finish` | When the user says they're done, or at session end |
| `/summary` | When the user asks for a recap of branch work |
| `/configure` | When the user wants to change git-pilot settings |
