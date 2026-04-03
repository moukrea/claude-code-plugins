---
name: init
description: "Initialize git-master configuration for the current project"
argument-hint: "[--quick]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Skill
---

## Pre-flight Checks

Before doing anything:

1. Verify the current directory is a git repository (`git rev-parse --is-inside-work-tree`). If not, abort with: "Not a git repository. Run `git init` first or navigate to a git repo."
2. Check if `.git-master.yml` already exists in the project root.
   - If it exists, show its contents and ask: "A git-master configuration already exists. Overwrite it? [y/N]"
   - If the user declines, abort.

## Default Mode (no arguments)

Invoke the **setting-up** skill to run the interactive configuration wizard:

> Use the `Skill` tool to invoke `setting-up`.

The setting-up skill handles all detection, prompting, and file creation. No additional work is needed here after invocation.

## Quick Mode (`--quick`)

When `$ARGUMENTS` contains `--quick`, perform automatic setup without interactive prompts.

### 1. Auto-detect Platform

```bash
git remote -v 2>/dev/null
```

Determine provider:
- `github.com` or `github.` = `github`
- `gitlab.com` or `gitlab.` = `gitlab`
- `gitea.` or `codeberg.org` = `gitea`
- `bitbucket.org` = `bitbucket`
- Otherwise = `auto`

### 2. Auto-detect CI

Check for CI configuration files:
- `.github/workflows/*.yml` = `github_actions`
- `.gitlab-ci.yml` = `gitlab_ci`
- Otherwise = `auto`

### 3. Auto-detect Commit Convention

Analyze the last 20 commit messages:

```bash
git log --oneline -20
```

Score each convention:
- **conventional**: Messages matching `type: subject` or `type(scope): subject` where type is a standard conventional commit type.
- **angular**: Same as conventional but with strict Angular types (`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`).
- **gitmoji**: Messages starting with an emoji or `:emoji_name:`.
- **freeform**: Default if nothing else matches with >50% confidence.

Pick the convention with the highest match rate (must be >50%).

### 4. Detect Scopes

If the convention is conventional or angular and scopes are present in the commit history, extract the unique scopes used.

### 5. Detect Protected Branches

```bash
git branch -r 2>/dev/null
```

Identify which of `main`, `master`, `develop` exist as remote branches.

### 6. Write Config

Create `.git-master.yml` with only the detected settings that differ from defaults:

```yaml
# git-master configuration (auto-generated with --quick)
# Customize: /git-master:config set key=value
# Full setup: /git-master:init

provider:
  type: <detected>

pipeline:
  provider: <detected>
```

Only include sections where detected values differ from defaults.

### 7. Report

Display what was detected and written:

```
git-master quick setup complete!

  Config:      .git-master.yml (created)
  Provider:    github (detected from remote)
  CI:          github_actions (3 workflows found)
  Convention:  conventional (85% of recent commits match)
  Branches:    main, develop (protected)

For full interactive setup: /git-master:init
To view config: /git-master:config show
```
