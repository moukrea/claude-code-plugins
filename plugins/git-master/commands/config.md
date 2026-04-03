---
name: config
description: "View or edit git-master configuration for the current project"
argument-hint: "[show | set key=value | reset]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
---

Parse `$ARGUMENTS` to determine the subcommand. Default to `show` if no arguments are provided.

## Subcommand: `show` (or no arguments)

1. Check if `$GIT_MASTER_CONFIG_PATH` is set and the file exists. If not, check for `.git-master.yml` in the current working directory.
2. If no project config exists:
   - Display: "No project configuration found. Using defaults."
   - Show a summary of the most important default settings (provider, commit convention, PR settings, review modes).
   - Suggest: "Run `/git-master:init` to create a project configuration."
   - Stop here.
3. If config exists, read it and also read the defaults from `${CLAUDE_PLUGIN_ROOT}/defaults/config.yml`.
4. Display a merged view showing each configured setting with its source:

```
git-master configuration (project: .git-master.yml)

Provider:
  type:              github          [project]
  host:              (default)       [default]
  fallback_enabled:  true            [default]

Commit:
  convention:        conventional    [default]
  scope_required:    true            [project]
  scopes:            api, web, cli   [project]
  subject.max_length: 72            [default]

PR:
  draft:             true            [project]
  merge_strategy:    squash          [default]
  reviewers.fallback: @tech-lead    [project]

Review:
  adversarial:       true            [default]
  security:          true            [default]
  performance:       true            [project]

Pipeline:
  provider:          auto            [default]
  auto_diagnose:     true            [default]
```

Only show settings that are either configured in the project file or are commonly important. Do not dump the entire defaults file.

## Subcommand: `set key=value`

1. Parse the key and value from `$ARGUMENTS`. The key uses dot notation (e.g., `commit.scope_required=true`, `pr.draft=false`).
2. Validate the key exists in the schema (reference `${CLAUDE_PLUGIN_ROOT}/defaults/config.yml`). If the key is invalid, show an error with the closest matching valid key.
3. Validate the value type:
   - Booleans: accept `true`/`false`, `yes`/`no`, `on`/`off`
   - Integers: must be numeric and within valid range
   - Strings: accept as-is
   - Arrays: accept comma-separated values (e.g., `commit.scopes=api,web,cli`)
4. Read the existing `.git-master.yml` if it exists, or start with an empty document.
5. Set the value at the correct nesting level. For example, `commit.scope_required=true` becomes:
   ```yaml
   commit:
     scope_required: true
   ```
6. Write the updated file.
7. Display: "Set `commit.scope_required` to `true` in `.git-master.yml`"

Handle multiple `set` operations in one call: `set commit.scope_required=true pr.draft=false`.

## Subcommand: `reset`

1. Check if `.git-master.yml` exists in the project root.
2. If it does not exist: "No project configuration to reset."
3. If it exists, show the current config contents and ask for confirmation: "This will delete `.git-master.yml` and revert all settings to defaults. Continue? [y/N]"
4. On confirmation, delete the file.
5. Display: "Project configuration reset. All settings reverted to defaults."

## Error Handling

- If the config file has invalid YAML syntax, report the parse error and suggest fixing it manually or running `reset`.
- If a `set` key path would conflict with an existing value type (e.g., setting `commit.types=feat` when it is an array), warn and ask for confirmation.
