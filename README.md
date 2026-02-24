# moukrea-plugins

Productivity and security plugins for [Claude Code](https://claude.ai/code).

## Plugins

### opaq — Secure Credential Access

Gives Claude Code secure access to your credentials without ever exposing secret values in the conversation, shell history, or files.

**What it does:**

- Teaches Claude the `opaq search` + `opaq run` workflow via a skill file
- Blocks direct access to the encrypted store and OS keychain via hooks
- Auto-wraps commands containing `{{SECRET}}` placeholders with `opaq run --`
- Prevents Claude from writing placeholder patterns to files

**In practice:**

```
You: "Deploy the app to production"

Claude: Let me find the deployment credentials.
        $ opaq search deploy
        #   {{DEPLOY_TOKEN}}    Production deployment API token
        $ opaq run -- curl -X POST -H "Authorization: Bearer {{DEPLOY_TOKEN}}" ...
```

The secret value is injected at runtime and scrubbed from all output. Claude never sees it.

Requires the [opaq](https://github.com/moukrea/opaq) binary installed on your system.

### git-pilot — Git Workflow Autopilot

Manages the full git workflow lifecycle automatically — branch creation, commit formatting, push prompts, and merge request creation.

**What it does:**

- Enforces branch naming conventions and prevents direct commits to the default branch
- Validates commit messages against configurable patterns (conventional commits by default)
- Prompts to push after every commit and offers merge request creation at session end
- Provides `/branch`, `/finish`, `/summary`, and `/configure` skills

**In practice:**

```
You: "Add dark mode support"

Claude: [git-pilot] On default branch 'main'. Prompt the user to create
        a branch before making changes.
        → Creates feat/add-dark-mode-support
        → Works, commits with validated messages
        → Prompts to push after each commit
        → Offers to create a PR when done
```

Configuration via `~/.claude/git-pilot.json` (global) or `.claude/git-pilot.json` (per-project).

### craft — Autonomous Implementation Prompts

Generates orchestration prompts that coordinate agent teams to implement entire projects from a technical specification.

**What it does:**

- Analyzes a technical spec and breaks it into self-contained module documents
- Designs a bottom-up build order and task dependency graph
- Generates a `PROMPT.md` that orchestrates multi-phase agent teams

**Usage:**

```
/craft @TECHNICAL-SPEC.md
```

Or describe what you want to build:

```
/craft A CLI tool that converts markdown files to PDF with custom themes
```

craft will generate a spec first, then produce the orchestration prompt.

## Installation

### Remote (recommended)

Add the marketplace source (one-time):

```
/plugin marketplace add moukrea/claude-code-plugins
```

Install plugins:

```
/plugin install opaq@moukrea-plugins
/plugin install craft@moukrea-plugins
/plugin install git-pilot@moukrea-plugins
```

### From a local clone

```bash
git clone https://github.com/moukrea/claude-code-plugins.git
```

Add the local directory as a marketplace source:

```
/plugin marketplace add ./claude-code-plugins
```

Install plugins:

```
/plugin install opaq@moukrea-plugins
/plugin install craft@moukrea-plugins
/plugin install git-pilot@moukrea-plugins
```

## How Plugins Work

### Skills

Skills are markdown files that teach Claude when and how to use a tool. They include:

- **Trigger conditions** — when the skill should activate (e.g., "when a task requires credentials not in the environment")
- **Workflow instructions** — step-by-step usage
- **Security rules** — constraints Claude must follow
- **Examples** — concrete command patterns

### Hooks

Hooks intercept Claude's tool calls before execution. Examples:

| Plugin | Hook | Trigger | Action |
|--------|------|---------|--------|
| opaq | Bash guard | Any Bash command | Blocks store/keychain access, auto-wraps `{{SECRET}}` commands |
| opaq | File guard | Write, Edit, MultiEdit | Blocks writing `{{SECRET}}` placeholders to files |
| opaq | Session start | New session | Announces opaq availability |
| git-pilot | Session start | New session | Detects branch state, prompts for branch creation |
| git-pilot | Pre-commit | `git commit` | Validates commit message format and body policy |
| git-pilot | Post-bash | `git commit` | Prompts to push unpushed commits |
| git-pilot | Session stop | Session end | Shows work summary, offers push and MR creation |

## Plugin Structure

Each plugin lives in `plugins/<name>/` and contains:

```
plugins/<name>/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest (name, version, description)
├── skills/
│   └── <skill-name>/
│       └── SKILL.md         # Skill definition with YAML frontmatter
├── hooks/
│   └── hooks.json           # Hook definitions (optional)
└── scripts/
    └── *.sh                 # Hook implementation scripts (optional)
```

The root `.claude-plugin/marketplace.json` is the registry that lists all available plugins.

## License

[MIT](LICENSE)
