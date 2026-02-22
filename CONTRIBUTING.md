# Contributing to moukrea-plugins

Thank you for your interest in contributing. This guide covers how to add new plugins, modify existing ones, and work with the CI/CD pipeline.

## Prerequisites

- [Claude Code](https://claude.ai/code) (for testing plugins)
- `jq` on your PATH
- [ShellCheck](https://www.shellcheck.net/) (for linting hook scripts)

## Repository Structure

```
claude-code-plugins/
├── .claude-plugin/
│   └── marketplace.json         # Central plugin registry
├── .github/
│   ├── scripts/
│   │   ├── validate-plugins.sh  # PR validation script
│   │   ├── detect-changes.sh    # Change detection for CI
│   │   └── bump-plugin.sh       # Auto version bumping
│   └── workflows/
│       ├── pr.yml               # PR validation
│       ├── release.yml          # Auto-release on main
│       └── tag-release.yml      # GitHub release creation
└── plugins/
    ├── opaq/                    # Credential security plugin
    └── craft/                   # Prompt generation plugin
```

## Adding a New Plugin

### 1. Create the plugin directory

```
plugins/<your-plugin>/
├── .claude-plugin/
│   └── plugin.json
└── skills/
    └── <skill-name>/
        └── SKILL.md
```

### 2. Write the plugin manifest

Create `plugins/<your-plugin>/.claude-plugin/plugin.json`:

```json
{
  "name": "<your-plugin>",
  "version": "0.1.0",
  "description": "Short description of what the plugin does.",
  "skills": "./skills/"
}
```

If your plugin uses hooks, add:

```json
{
  "name": "<your-plugin>",
  "version": "0.1.0",
  "description": "Short description of what the plugin does.",
  "skills": "./skills/",
  "hooks": "./hooks/hooks.json"
}
```

### 3. Write the skill file

Create `plugins/<your-plugin>/skills/<skill-name>/SKILL.md` with YAML frontmatter:

```markdown
---
name: <skill-name>
description: When this skill should activate. Be specific about trigger conditions.
---

# Skill Title

Instructions for Claude on how to use this skill.
```

Frontmatter fields:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Skill identifier |
| `description` | Yes | Trigger conditions — when should Claude use this? |
| `user-invocable` | No | Set to `true` if invoked via `/skill-name` |
| `argument-hint` | No | Hint shown to the user (e.g., `@file.md or description`) |
| `disable-model-invocation` | No | Set to `true` to prevent automatic activation |

### 4. Register in the marketplace

Add an entry to `.claude-plugin/marketplace.json`:

```json
{
  "name": "<your-plugin>",
  "source": "./plugins/<your-plugin>",
  "description": "Same description as plugin.json",
  "version": "0.1.0",
  "author": { "name": "your-name" },
  "homepage": "https://github.com/...",
  "repository": "https://github.com/moukrea/claude-code-plugins",
  "license": "MIT",
  "keywords": ["relevant", "keywords"],
  "category": "security|productivity|developer-tools|..."
}
```

The version in `marketplace.json` must match the version in `plugin.json`.

### 5. Validate

Run the validation script before submitting a PR:

```bash
.github/scripts/validate-plugins.sh
```

This checks:
- JSON syntax of `marketplace.json` and all `plugin.json` files
- Required fields present
- Version consistency between marketplace and plugin manifests
- ShellCheck passes on all `.sh` files
- SKILL.md files have YAML frontmatter

## Writing Hooks

Hooks are shell scripts that intercept Claude's tool calls. They receive JSON on stdin and must output JSON.

### Hook types

| Event | When it fires |
|-------|--------------|
| `PreToolUse` | Before Claude executes a tool (Bash, Write, Edit, etc.) |
| `SessionStart` | When a new Claude Code session begins |

### Hook input (stdin)

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "the command claude wants to run"
  }
}
```

### Hook output (stdout)

To **block** a tool call:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Explain why this was blocked."
  }
}
```

To **allow and modify** a tool call:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "updatedInput": { "command": "modified command" }
  }
}
```

To **allow without changes**, exit with code 0 and no output.

### Hook script conventions

- Use `#!/usr/bin/env bash` and `set -euo pipefail`
- Read input with `INPUT=$(cat)` and parse with `jq`
- Keep scripts focused — one responsibility per hook
- All scripts must pass ShellCheck

## Commit Messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/). The CI pipeline uses commit messages to auto-bump plugin versions:

| Prefix | Version Bump | Example |
|--------|-------------|---------|
| `feat:` | Minor | `feat(opaq): add JSON output to search` |
| `fix:`, `perf:` | Patch | `fix(craft): handle empty spec files` |
| `BREAKING CHANGE:` | Major | `feat(opaq)!: change hook output format` |

Scope your commits to a plugin name when the change is plugin-specific.

## Pull Requests

1. Fork the repository and create a branch from `main`
2. Make your changes
3. Run `.github/scripts/validate-plugins.sh` and ensure it passes
4. Run `shellcheck` on any new or modified shell scripts
5. Write a clear PR description
6. Submit the PR

The CI pipeline will automatically run validation on your PR.

## Versioning

Plugin versions are managed automatically by the CI pipeline:

- On merge to `main`, `bump-plugin.sh` analyzes commit messages since the last tag
- Versions are bumped per-plugin based on Conventional Commit prefixes
- Tags follow the format `<plugin-name>-v<version>` (e.g., `opaq-v0.2.0`)
- GitHub releases are created automatically from tags

Do not manually edit version numbers in `plugin.json` or `marketplace.json` — the pipeline handles it.
