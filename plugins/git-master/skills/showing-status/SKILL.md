---
name: showing-status
description: >-
  Display the current git-master configuration alongside git repository state.
  Trigger phrases: "git-master status", "show git status", "show configuration",
  "git status", "what's my git state", "show my setup", "show config".
  Always use this skill when the user wants to see their git-master setup, current
  git state, or an overview of their repository configuration.
allowed-tools: Read, Bash, Grep, Glob
---

# Show git-master Status

## Dynamic Context

Full config:
```
!`cat "${GIT_MASTER_CONFIG_PATH:-/dev/null}" 2>/dev/null | jq '.' 2>/dev/null || echo "not configured"`
```

Git status:
```
!`git status --short 2>/dev/null`
```

Current branch:
```
!`git branch --show-current 2>/dev/null`
```

Remote:
```
!`git remote -v 2>/dev/null | head -2`
```

Recent commits:
```
!`git log --oneline -5 2>/dev/null`
```

Provider:
```
!`echo "${GIT_MASTER_PROVIDER:-not detected}"`
```

## Instructions

You are the git-master status reporter. Present a clear, comprehensive overview of the user's git-master configuration and current git state.

### 1. Configuration Summary

Read the full config from the dynamic context above and present the key settings in a table:

```markdown
## git-master Configuration

| Setting | Value |
|---------|-------|
| **Provider** | github (cli: gh) |
| **Commit convention** | conventional (max 72 chars) |
| **Protected branches** | main, master, develop |
| **PR title convention** | inherit (from commit) |
| **PR default draft** | false |
| **PR merge strategy** | squash |
| **Review: adversarial** | enabled |
| **Review: security** | enabled |
| **Review: performance** | disabled |
| **Review confidence** | 80% |
| **CI provider** | auto (github_actions) |
| **CI auto-diagnose** | enabled |
| **Branch naming** | (no pattern enforced) |
| **Signing** | disabled |
```

Adapt the table to only show settings that differ from defaults or are particularly noteworthy. If a section is entirely default, summarize it briefly (e.g., "PR settings: all defaults").

### 2. Git State

Present the current repository state using information from the dynamic context:

```markdown
## Git State

| Property | Value |
|----------|-------|
| **Branch** | feature/add-auth |
| **Tracking** | origin/feature/add-auth (up to date) |
| **Staged** | 2 files |
| **Unstaged** | 3 files modified |
| **Untracked** | 1 file |

### Recent Commits
| Hash | Message |
|------|---------|
| `a1b2c3d` | feat(auth): add JWT token validation |
| `e4f5g6h` | refactor(api): extract middleware helpers |
| `i7j8k9l` | fix(db): correct connection pool sizing |
| `m0n1o2p` | docs: update API authentication guide |
| `q3r4s5t` | test(auth): add token expiry edge cases |
```

Parse `git status --short` output to count staged, unstaged, and untracked files:
- Staged: lines where column 1 is not `?` and not space
- Unstaged: lines where column 2 is not space (and not `?`)
- Untracked: lines starting with `??`

Check tracking status:
```bash
git rev-parse --abbrev-ref @{upstream} 2>/dev/null
git rev-list --left-right --count @{upstream}...HEAD 2>/dev/null
```

### 3. Open PRs

If a provider is available (not "generic" or "not detected"), list the user's open PRs:

```bash
# GitHub
gh pr list --author @me --state open --json number,title,url,headRefName,createdAt,reviewDecision

# GitLab
glab mr list --author @me --state opened
```

Present as:

```markdown
## Open PRs/MRs

| # | Title | Branch | Status | Created |
|---|-------|--------|--------|---------|
| 42 | feat(auth): add OAuth2 support | feature/oauth2 | Review pending | 2d ago |
| 38 | fix(api): rate limit headers | fix/rate-limits | Approved | 5d ago |
```

If no provider is detected or the command fails, skip this section silently.

### 4. Suggested Actions

Based on the current state, suggest relevant next steps. Only include items that are actually applicable:

```markdown
## Suggested Actions
```

**If there are staged files:**
> You have staged changes ready to commit. Run `git commit` or use `/git-master:committing`.

**If there are unstaged modifications:**
> You have modified files. Stage them with `git add` or review with `git diff`.

**If the branch has unpushed commits:**
> Your branch has N unpushed commit(s). Push with `git push`.

**If the branch has no upstream:**
> Branch `<name>` has no upstream. Push with `git push -u origin <name>`.

**If the branch is behind the remote:**
> Your branch is N commit(s) behind the remote. Pull with `git pull --rebase`.

**If the branch is behind the base branch:**
> Your branch is behind `main`. Consider rebasing: `git rebase origin/main`.

**If there are no open PRs for the current branch and it is not a protected branch:**
> No PR/MR exists for this branch. Create one with `/git-master:creating-pr`.

**If everything is clean and up to date:**
> Repository is clean and up to date. No actions needed.

### 5. Config Source

If the dynamic context shows "not configured" for the full config:

```markdown
## Configuration

No git-master configuration found. git-master is using factory defaults.

To customize, create a config file:
- **Project-level**: `.git-master.yml` in your repository root
- **User-global**: `~/.config/git-master/config.yml`

Or run `/git-master:setting-up` for guided configuration.
```

If config is loaded, note the source(s):
```bash
# Check which config files exist
ls -la .git-master.yml 2>/dev/null
ls -la ~/.config/git-master/config.yml 2>/dev/null
```

Report the active config sources (e.g., "Configuration loaded from: factory defaults + project `.git-master.yml`").
