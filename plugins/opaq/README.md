# opaq — Secure Credential Access

Gives Claude Code secure access to your credentials without ever exposing secret values in the conversation, shell history, or files.

## What it does

- Teaches Claude the `opaq search` + `opaq run` workflow via a skill file
- Blocks direct access to the encrypted store and OS keychain via hooks
- Auto-wraps commands containing `{{SECRET}}` placeholders with `opaq run --`
- Prevents Claude from writing placeholder patterns to files

## In practice

```
You: "Deploy the app to production"

Claude: Let me find the deployment credentials.
        $ opaq search deploy
        #   {{DEPLOY_TOKEN}}    Production deployment API token
        $ opaq run -- curl -X POST -H "Authorization: Bearer {{DEPLOY_TOKEN}}" ...
```

The secret value is injected at runtime and scrubbed from all output. Claude never sees it.

## Requirements

The [opaq](https://github.com/moukrea/opaq) binary must be installed on your system.

## Hooks

| Hook | Trigger | Action |
|------|---------|--------|
| Bash guard | Any Bash command | Blocks store/keychain access, auto-wraps `{{SECRET}}` commands |
| File guard | Write, Edit, MultiEdit | Blocks writing `{{SECRET}}` placeholders to files |
| Session start | New session | Announces opaq availability |

## Installation

```
/plugin install opaq@moukrea-plugins
```
