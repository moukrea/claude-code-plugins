# git-pilot — Git Workflow Autopilot

Manages the full git workflow lifecycle automatically — branch creation, commit formatting, push prompts, and merge request creation.

## What it does

- Enforces branch naming conventions and prevents direct commits to the default branch
- Validates commit messages against configurable patterns (conventional commits by default)
- Prompts to push after every commit and offers merge request creation at session end
- Provides `/branch`, `/finish`, `/summary`, and `/configure` skills

## In practice

```
You: "Add dark mode support"

Claude: [git-pilot] On default branch 'main'. Prompt the user to create
        a branch before making changes.
        -> Creates feat/add-dark-mode-support
        -> Works, commits with validated messages
        -> Prompts to push after each commit
        -> Offers to create a PR when done
```

## Skills

| Skill | Description |
|-------|-------------|
| `/branch` | Create a new branch using the configured naming pattern |
| `/finish` | Commit remaining changes, push, and optionally create a merge request |
| `/summary` | Show a summary of work done on the current branch |
| `/configure` | Change git-pilot settings using natural language |

## Hooks

| Hook | Trigger | Action |
|------|---------|--------|
| Session start | New session | Detects branch state, prompts for branch creation |
| Pre-commit | `git commit` | Validates commit message format and body policy |
| Post-bash | `git commit` | Prompts to push unpushed commits |
| Session stop | Session end | Shows work summary, offers push and MR creation |

## Configuration

Settings can be defined at two levels (local overrides global):

- **Global**: `~/.claude/git-pilot.json`
- **Per-project**: `.claude/git-pilot.json`

Use `/configure` to change settings interactively, or edit the JSON files directly. Configuration covers branch naming, commit format, remote behavior, merge request defaults, and more.

## Installation

```
/plugin install git-pilot@moukrea-plugins
```
