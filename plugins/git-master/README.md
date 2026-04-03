# git-master

A Claude Code plugin for comprehensive git workflow control.

## Features

- **Commit conventions** — Enforce Conventional Commits, Angular, Gitmoji, or custom patterns. Validates messages, types, scopes, and subject length via hooks.
- **PR/MR automation** — Create pull requests (GitHub) and merge requests (GitLab) with configurable templates, auto-labels, size labels, reviewer assignment, and description auto-population from commits.
- **Multi-provider support** — Works with GitHub (`gh`), GitLab (`glab`), Gitea (`tea`), Bitbucket, and private instances. Auto-detects provider from remote URL with CLI fallback chains.
- **Code review** — Standard review checklist plus specialized review agents:
  - **Adversarial reviewer** (opus) — devil's advocate that finds edge cases, race conditions, and logic errors
  - **Security reviewer** — OWASP-focused analysis with CWE references
  - **Performance reviewer** — N+1 queries, memory leaks, algorithmic complexity
- **Pipeline diagnostics** — Fetch CI/CD failure logs, diagnose root causes, propose fixes, and retry failed jobs.
- **Hierarchical configuration** — YAML config at directory, project, user, and plugin levels with deep merge.

## Installation

```bash
# Local testing
claude --plugin-dir /path/to/git-master

# Or add to settings
# In ~/.claude/settings.json under "plugins"
```

## Configuration

Create `.git-master.yml` at your project root (or `~/.config/git-master/config.yml` for global defaults):

```yaml
commit:
  convention: conventional
  scope_required: false
  subject:
    max_length: 72

pr:
  draft: false
  auto_labels: true
  merge_strategy: squash

review:
  adversarial: true
  security: true

branch:
  protected: [main, master]
```

See `defaults/config.yml` for the full schema with all options.

### Config precedence (highest to lowest)

1. `GIT_MASTER_*` environment variables
2. `.git-master.yml` in current/ancestor directories
3. `.git-master.yml` at project root
4. `~/.config/git-master/config.yml`
5. Plugin defaults

## Skills (auto-triggered)

| Skill | Trigger phrases |
|-------|----------------|
| **committing** | "commit", "create a commit", "git commit" |
| **creating-pr** | "create PR", "open pull request", "create MR" |
| **reviewing-pr** | "review PR", "code review", "check this PR" |
| **monitoring-pr** | "check PR status", "is the pipeline passing" |
| **fixing-pipeline** | "fix pipeline", "fix CI", "fix the build" |
| **setting-up** | "set up git-master", "configure git-master" |
| **showing-status** | "git-master status", "show configuration" |

## Commands

| Command | Description |
|---------|-------------|
| `/git-master:config` | View or edit configuration |
| `/git-master:init` | Initialize config for current project |

## Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| adversarial-reviewer | opus | Hostile code review finding real bugs |
| security-reviewer | sonnet | Security-focused OWASP analysis |
| performance-reviewer | sonnet | Performance and scalability review |
| pipeline-doctor | sonnet | CI/CD failure diagnosis |

## Hooks

| Event | Purpose |
|-------|---------|
| SessionStart | Load config, detect provider, inject context |
| PreToolUse (Bash) | Validate commit messages, block protected branch push, block force push, validate PR titles |
| PostToolUse (Bash) | Guidance after merge conflicts, push rejections, successful commits |
| Stop | Warn about staged uncommitted files, unresolved conflicts, active rebase/merge |

## Provider support

| Provider | CLI | API fallback | Status |
|----------|-----|-------------|--------|
| GitHub | `gh` | REST API | Full |
| GitLab | `glab` | API v4 | Full |
| Gitea | `tea` | API v1 | Full |
| Bitbucket | — | REST API | Partial |
| Generic | `git` | — | Local only |

## License

MIT
