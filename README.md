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

### From the Claude Code marketplace

```bash
claude plugin install moukrea-plugins/opaq
claude plugin install moukrea-plugins/craft
```

### From a local clone

```bash
git clone https://github.com/moukrea/claude-code-plugins.git

# Register the local directory as a marketplace source
claude marketplace add ./claude-code-plugins

# Install plugins
claude plugin install opaq
claude plugin install craft
```

## How Plugins Work

### Skills

Skills are markdown files that teach Claude when and how to use a tool. They include:

- **Trigger conditions** — when the skill should activate (e.g., "when a task requires credentials not in the environment")
- **Workflow instructions** — step-by-step usage
- **Security rules** — constraints Claude must follow
- **Examples** — concrete command patterns

### Hooks

Hooks intercept Claude's tool calls before execution. The opaq plugin uses hooks to:

| Hook | Trigger | Action |
|------|---------|--------|
| Bash guard | Any Bash command | Blocks store/keychain access, blocks user-only subcommands, auto-wraps `{{SECRET}}` commands |
| File guard | Write, Edit, MultiEdit | Blocks writing `{{SECRET}}` placeholders to files |
| Session start | New session | Announces opaq availability |

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
