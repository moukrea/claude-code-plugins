---
name: setting-up
description: >-
  Interactive configuration wizard for git-master. Trigger phrases: "set up
  git-master", "configure git-master", "initialize git-master", "git-master
  setup", "configure my git workflow", "set up commit conventions". Detects
  project context and walks through settings interactively.
argument-hint: ""
allowed-tools:
  - Read
  - Bash
  - Glob
  - Write
  - Edit
disable-model-invocation: true
---

## Instructions

Guide the user through setting up git-master for their project. Be concise and helpful. Only write settings that differ from the defaults.

### 1. Detect Context

Run all of the following checks in parallel to gather project context:

**Existing config:**
- Check if `.git-master.yml` exists in the project root.
- If it exists, read it and note which settings are already configured.

**Platform detection:**
- Run `git remote -v` and determine the provider:
  - `github.com` or `github.` in URL = GitHub
  - `gitlab.com` or `gitlab.` in URL = GitLab
  - `gitea.` or `codeberg.org` in URL = Gitea
  - `bitbucket.org` in URL = Bitbucket
  - Otherwise = unknown (ask the user)

**CI configuration:**
- Check for `.github/workflows/` directory (GitHub Actions)
- Check for `.gitlab-ci.yml` (GitLab CI)
- Check for `Jenkinsfile` (Jenkins)
- Check for `.circleci/` directory (CircleCI)
- Check for `.travis.yml` (Travis CI)
- Check for `azure-pipelines.yml` (Azure DevOps)

**Existing conventions:**
- Check for `commitlint.config.js`, `commitlint.config.cjs`, `commitlint.config.mjs`, `commitlint.config.ts`
- Check for `.commitlintrc`, `.commitlintrc.json`, `.commitlintrc.yml`
- Check `package.json` for a `commitlint` field
- Check for `.czrc` or `cz.json` (Commitizen)

**Commit history analysis:**
- Run `git log --oneline -20` and analyze the patterns:
  - Conventional commits? (`type: subject` or `type(scope): subject`)
  - Gitmoji? (commits starting with emoji)
  - Angular style? (`type(scope): subject` with angular types)
  - Freeform? (no consistent pattern)

### 2. Present Detection Results

Show the user what was auto-detected in a clear summary:

```
Detected Configuration:
  Platform:    GitHub (github.com/org/repo)
  CI:          GitHub Actions (3 workflows found)
  Convention:  Conventional Commits (18/20 recent commits match)
  Existing:    No .git-master.yml found
```

If a `.git-master.yml` already exists, ask if they want to reconfigure from scratch or modify specific settings.

### 3. Walk Through Settings

Use clear prompts for each setting group. Only ask about settings that are ambiguous or have no clear detected value. Skip settings where the detection is confident.

**Commit Convention:**
- If detected with high confidence, confirm: "Your commits follow conventional commits. Keep this? [Y/n]"
- If unclear, ask: "Which commit convention do you use?"
  - `conventional` - Conventional Commits (feat, fix, docs, ...)
  - `angular` - Angular style (similar to conventional with stricter types)
  - `gitmoji` - Emoji-prefixed commits
  - `freeform` - No enforced convention
- If conventional or angular: "Require scopes? [y/N]" and "Specific allowed scopes? (comma-separated, or empty for any)"

**PR Template:**
- "PR description template style?"
  - `default` - Summary + Changes + Test plan sections
  - `minimal` - Summary only
  - `detailed` - Summary + Changes + Test plan + Screenshots + Breaking changes

**Review Modes:**
- "Enable adversarial reviewer (devil's advocate challenge)? [Y/n]"
- "Enable security-focused review? [Y/n]"
- "Enable performance-focused review? [y/N]"

**Protected Branches:**
- Show detected default branch: "Protected branches: main, master, develop. Modify? [y/N]"

**Default Reviewers:**
- "Default reviewers to assign to PRs? (comma-separated GitHub usernames, or empty for none)"

### 4. Write Config

Create `.git-master.yml` at the project root. Only include settings that differ from the defaults in `defaults/config.yml`.

Example of a minimal config:

```yaml
# git-master project configuration
# See defaults: https://github.com/user/git-master/blob/main/defaults/config.yml

provider:
  type: github

commit:
  scope_required: true
  scopes:
    - api
    - ui
    - core

pr:
  draft: true
  reviewers:
    fallback:
      - "@lead-dev"

review:
  performance: true
```

Use comments sparingly and only where they add clarity.

### 5. Git Ignore Decision

Ask the user:
- "This config contains **team settings** (commit convention, PR template, review modes). Recommend committing it so the whole team shares the same config."
- "If it contains **personal preferences** only, add it to `.gitignore` instead."

Based on their answer:
- **Commit**: No action needed (file is already tracked).
- **Ignore**: Append `.git-master.yml` to `.gitignore` (create the file if needed, append if it exists).

### 6. Confirm

Display the final config file contents and summarize:

```
git-master configured successfully!

  Config file: .git-master.yml
  Convention:  conventional (scopes required)
  PR style:    default template, draft by default
  Reviews:     adversarial + security + performance
  Protected:   main, develop

To modify later:
  /git-master:config set key=value
  /git-master:config show
  Or edit .git-master.yml directly.
```

## Notes

- Never overwrite an existing `.git-master.yml` without asking first.
- If the user cancels mid-setup, do not write any files.
- Keep the generated config file as short as possible. Defaults do not need to be repeated.
- Reference the full config schema in `references/config-schema.md` when explaining options.
