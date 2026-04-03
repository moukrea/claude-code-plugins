# git-master Configuration Schema Reference

All settings can be placed in `.git-master.yml` at the project root or `~/.config/git-master/config.yml` for global defaults. Project config overrides global, which overrides built-in defaults.

## Provider

| Field                    | Type       | Default    | Values                                        | Description                                    |
|--------------------------|------------|------------|-----------------------------------------------|------------------------------------------------|
| `provider.type`          | string     | `auto`     | `auto`, `github`, `gitlab`, `gitea`, `bitbucket` | Git hosting provider (auto-detected from remote) |
| `provider.host`          | string     | `""`       | any URL                                       | Custom host for self-hosted instances          |
| `provider.cli_preference`| string[]   | `[gh, glab, tea, git]` | CLI tool names                     | Fallback order for CLI tools                   |
| `provider.token_env`     | string     | `""`       | env var name                                  | Environment variable holding API token         |
| `provider.fallback_enabled` | boolean | `true`     | `true`, `false`                               | Try next CLI tool if preferred one fails       |

## Commit

| Field                         | Type       | Default          | Values                                    | Description                                     |
|-------------------------------|------------|------------------|-------------------------------------------|-------------------------------------------------|
| `commit.convention`           | string     | `conventional`   | `conventional`, `angular`, `gitmoji`, `custom` | Commit message convention to enforce        |
| `commit.types`                | string[]   | `[feat, fix, ...]` | any strings                             | Allowed commit types                            |
| `commit.scopes`               | string[]   | `[]`             | any strings                               | Allowed scopes (empty = any scope allowed)      |
| `commit.scope_required`       | boolean    | `false`          | `true`, `false`                           | Whether scope is mandatory                      |
| `commit.subject.max_length`   | integer    | `72`             | 1-200                                     | Max characters for subject line                 |
| `commit.subject.case`         | string     | `lower`          | `lower`, `upper`, `sentence`, `none`      | Case style for subject line                     |
| `commit.subject.no_trailing_period` | boolean | `true`        | `true`, `false`                           | Disallow trailing period in subject             |
| `commit.body.required`        | boolean    | `false`          | `true`, `false`                           | Whether commit body is mandatory                |
| `commit.body.max_line_length` | integer    | `100`            | 1-500                                     | Max characters per body line                    |
| `commit.body.require_references` | string  | `""`             | regex pattern                             | Regex for required ticket references            |
| `commit.breaking.footer_required` | boolean | `true`          | `true`, `false`                           | Require BREAKING CHANGE footer for breaking changes |
| `commit.breaking.exclamation_mark` | boolean | `true`         | `true`, `false`                           | Allow `!` after type/scope for breaking changes |
| `commit.signing.enabled`      | boolean    | `false`          | `true`, `false`                           | Enable commit signing                           |
| `commit.signing.method`       | string     | `gpg`            | `gpg`, `ssh`                              | Signing method                                  |
| `commit.signing.key`          | string     | `""`             | key ID or path                            | Signing key identifier                          |
| `commit.skip_patterns`        | string[]   | `[^Merge, ...]`  | regex patterns                            | Patterns for commits that bypass convention check |
| `commit.ai_attribution`       | boolean    | `false`          | `true`, `false`                           | Include AI attribution in commit messages       |
| `commit.custom_pattern`       | string     | `""`             | regex with named groups                   | Custom convention regex (for `convention: custom`) |
| `commit.custom_description`   | string     | `""`             | any string                                | Human-readable description of custom convention |
| `commit.emoji_prefix`         | object     | `null`           | `{ type: "emoji_name" }`                  | Map commit types to emoji prefixes              |
| `commit.pre_checks.enabled`   | boolean    | `false`          | `true`, `false`                           | Run checks before committing                    |
| `commit.pre_checks.commands`  | object[]   | `[]`             | `[{command, name, required}]`             | Commands to run before commit                   |

## Branch

| Field                    | Type       | Default                      | Values          | Description                                  |
|--------------------------|------------|------------------------------|-----------------|----------------------------------------------|
| `branch.protected`       | string[]   | `[main, master, develop]`    | branch names    | Branches that cannot be committed to directly |
| `branch.naming_pattern`  | string     | `""`                         | regex pattern   | Required pattern for branch names            |
| `branch.default_base`    | string     | `""`                         | branch name     | Default base branch (auto-detected if empty) |

## PR/MR

| Field                          | Type       | Default       | Values                                       | Description                                     |
|--------------------------------|------------|---------------|----------------------------------------------|-------------------------------------------------|
| `pr.title.convention`          | string     | `inherit`     | `inherit`, `conventional`, `custom`, `freeform` | PR title convention                           |
| `pr.title.custom_pattern`      | string     | `""`          | regex pattern                                | Custom PR title pattern                         |
| `pr.title.max_length`          | integer    | `72`          | 1-200                                        | Max characters for PR title                     |
| `pr.description.template`      | string     | *(see below)* | multiline string                             | PR description template with sections           |
| `pr.description.required_sections` | string[] | `[summary, test_plan]` | section names                       | Sections that must be filled in                 |
| `pr.auto_populate`             | boolean    | `true`        | `true`, `false`                              | Auto-fill description from commit messages      |
| `pr.draft`                     | boolean    | `false`       | `true`, `false`                              | Create PRs as draft by default                  |
| `pr.labels`                    | string[]   | `[]`          | label names                                  | Static labels applied to every PR               |
| `pr.auto_labels`               | boolean    | `true`        | `true`, `false`                              | Auto-assign labels based on changed files       |
| `pr.label_rules`               | object[]   | *(see defaults)* | `[{pattern, labels}]`                    | File pattern to label mapping rules             |
| `pr.size_labels.enabled`       | boolean    | `true`        | `true`, `false`                              | Add size labels based on lines changed          |
| `pr.size_labels.xs`            | integer    | `10`          | 1+                                           | Max lines for XS label                          |
| `pr.size_labels.s`             | integer    | `50`          | 1+                                           | Max lines for S label                           |
| `pr.size_labels.m`             | integer    | `200`         | 1+                                           | Max lines for M label                           |
| `pr.size_labels.l`             | integer    | `500`         | 1+                                           | Max lines for L label                           |
| `pr.size_labels.xl`            | integer    | `1000`        | 1+                                           | Max lines for XL label (above = XXL)            |
| `pr.reviewers.auto_assign`     | boolean    | `true`        | `true`, `false`                              | Auto-assign reviewers based on rules            |
| `pr.reviewers.rules`           | object[]   | `[]`          | `[{pattern, reviewers, required}]`           | File pattern to reviewer mapping                |
| `pr.reviewers.fallback`        | string[]   | `[]`          | usernames                                    | Fallback reviewers when no rule matches         |
| `pr.assignees`                 | string[]   | `[]`          | usernames                                    | Default PR assignees                            |
| `pr.team_reviewers`            | string[]   | `[]`          | team slugs                                   | Teams to request review from                    |
| `pr.target_branch`             | string     | `""`          | branch name                                 | Override target branch (empty = repo default)   |
| `pr.delete_branch_on_merge`    | boolean    | `true`        | `true`, `false`                              | Delete source branch after merge                |
| `pr.merge_strategy`            | string     | `squash`      | `merge`, `squash`, `rebase`                  | Default merge strategy                          |

## Review

| Field                          | Type       | Default       | Values                        | Description                                     |
|--------------------------------|------------|---------------|-------------------------------|-------------------------------------------------|
| `review.adversarial`           | boolean    | `true`        | `true`, `false`               | Enable adversarial (devil's advocate) reviewer  |
| `review.security`              | boolean    | `true`        | `true`, `false`               | Enable security-focused review                  |
| `review.performance`           | boolean    | `false`       | `true`, `false`               | Enable performance-focused review               |
| `review.checklist`             | string[]   | *(see defaults)* | checklist items            | Review checklist items                          |
| `review.security_patterns`     | object[]   | *(see defaults)* | `[{pattern, severity, message}]` | Regex patterns for security issues         |
| `review.performance_patterns`  | object[]   | *(see defaults)* | `[{pattern, message}]`    | Regex patterns for performance issues           |
| `review.confidence_threshold`  | integer    | `80`          | 0-100                         | Min confidence to report findings               |
| `review.max_files_per_review`  | integer    | `30`          | 1+                            | Suggest splitting PR above this file count      |
| `review.exclude_patterns`      | string[]   | *(see defaults)* | glob patterns              | Files to exclude from review                    |
| `review.language_rules`        | object     | `{}`          | `{ lang: [rules] }`          | Per-language review rules                       |
| `review.model`                 | string     | `sonnet`      | model names                   | Model for standard review agents                |
| `review.adversarial_model`     | string     | `opus`        | model names                   | Model for adversarial reviewer                  |

## Pipeline

| Field                           | Type       | Default           | Values                                       | Description                                  |
|---------------------------------|------------|-------------------|----------------------------------------------|----------------------------------------------|
| `pipeline.provider`             | string     | `auto`            | `auto`, `github_actions`, `gitlab_ci`, `none` | CI/CD provider                              |
| `pipeline.auto_diagnose`        | boolean    | `true`            | `true`, `false`                              | Auto-diagnose pipeline failures              |
| `pipeline.auto_suggest_fix`     | boolean    | `true`            | `true`, `false`                              | Suggest code fixes for failures              |
| `pipeline.poll_interval`        | integer    | `30`              | 5-300 (seconds)                              | Seconds between status checks                |
| `pipeline.max_wait`             | integer    | `600`             | 60-7200 (seconds)                            | Max seconds to wait for pipeline             |
| `pipeline.required_checks`      | string[]   | `[]`              | check names                                  | Checks that must pass (empty = all)          |
| `pipeline.ignored_checks`       | string[]   | `[]`              | check names                                  | Checks to ignore                             |
| `pipeline.max_auto_fix_attempts`| integer    | `3`               | 1-10                                         | Max automatic fix attempts before stopping   |

## Workflow

| Field                      | Type       | Default    | Values          | Description                                     |
|----------------------------|------------|------------|-----------------|-------------------------------------------------|
| `workflow.auto_stash`      | boolean    | `true`     | `true`, `false` | Stash uncommitted changes before operations     |
| `workflow.auto_fetch`      | boolean    | `true`     | `true`, `false` | Fetch remote before branch operations           |
| `workflow.rebase_on_pull`  | boolean    | `true`     | `true`, `false` | Use rebase instead of merge when pulling        |
| `workflow.prune_on_fetch`  | boolean    | `true`     | `true`, `false` | Prune deleted remote branches on fetch          |
| `workflow.default_remote`  | string     | `origin`   | remote name     | Default remote name                             |

## Example Configurations

### Minimal (solo developer)

```yaml
provider:
  type: github
```

### Team Project

```yaml
provider:
  type: github

commit:
  scope_required: true
  scopes: [api, web, cli, docs]

pr:
  draft: true
  reviewers:
    fallback: ["@tech-lead"]

review:
  adversarial: true
  security: true
```

### Enterprise

```yaml
provider:
  type: gitlab
  host: https://gitlab.corp.example.com

commit:
  convention: angular
  scope_required: true
  scopes: [core, auth, billing, notifications, infra]
  body:
    required: true
    require_references: "PROJ-\\d+"
  signing:
    enabled: true
    method: ssh

branch:
  naming_pattern: "^(feature|bugfix|hotfix|release)/[A-Z]+-\\d+-[a-z0-9-]+$"

pr:
  description:
    required_sections: [summary, test_plan, security]
  reviewers:
    rules:
      - pattern: "src/auth/**"
        reviewers: ["@security-team"]
        required: 2
      - pattern: "src/billing/**"
        reviewers: ["@billing-team"]
        required: 1
    fallback: ["@platform-team"]

review:
  adversarial: true
  security: true
  performance: true
  confidence_threshold: 70
  language_rules:
    python: ["Verify type hints on public functions"]
    go: ["Check error handling follows project conventions"]

pipeline:
  required_checks: [build, test, lint, security-scan]
  ignored_checks: [coverage-report]
```
