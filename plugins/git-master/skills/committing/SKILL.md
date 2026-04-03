---
name: committing
description: >-
  Smart git commit workflow with project-aware conventions. Use when the user
  says: "commit", "create a commit", "stage and commit", "git commit",
  "save my progress", "commit my changes", "commit this work",
  "commit with message", or asks to save/record changes to version control.
  Reads project config to enforce commit conventions, signing, and attribution
  rules automatically.
argument-hint: "[optional commit message or description]"
allowed-tools: Read, Bash, Grep, Glob
---

# Dynamic Context

**Commit config:**
!`cat "${GIT_MASTER_CONFIG_PATH:-/dev/null}" 2>/dev/null | jq '.commit' 2>/dev/null || echo "no config"`

**Git status:**
!`git status --short 2>/dev/null`

**Staged diff stat:**
!`git diff --cached --stat 2>/dev/null`

**Current branch:**
!`git branch --show-current 2>/dev/null`

**Recent commits (for style reference):**
!`git log --oneline -5 2>/dev/null`

---

# Smart Commit Workflow

Follow these steps in order. Do NOT skip steps.

## 1. Read Configuration

Parse the injected commit config above. Extract these settings (use defaults when missing):

| Setting | Default |
|---|---|
| `convention` | `conventional` |
| `subject.max_length` | `72` |
| `subject.case` | `lower` |
| `subject.no_trailing_period` | `true` |
| `scope_required` | `false` |
| `scopes` | `[]` (any scope allowed) |
| `types` | `[feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert]` |
| `body.required` | `false` |
| `body.max_line_length` | `100` |
| `body.require_references` | `""` |
| `breaking.footer_required` | `true` |
| `breaking.exclamation_mark` | `true` |
| `signing.enabled` | `false` |
| `signing.method` | `gpg` |
| `ai_attribution` | `false` |
| `custom_pattern` | `""` |
| `emoji_prefix` | `null` |

## 2. Assess Working Tree State

Check the injected git status and staged diff stat:

- **Nothing to commit** (no staged, unstaged, or untracked files): Tell the user there is nothing to commit and stop.
- **Nothing staged but changes exist**: List the changed/untracked files and ask the user what they want to stage. Do NOT auto-stage everything.
- **Files already staged**: Proceed to step 3. If there are also unstaged changes, mention them and ask if the user wants to include any of those as well.

## 3. Protected Branch Check

Compare the current branch against the configured `branch.protected` list (default: `main`, `master`, `develop`).

If on a protected branch:
- Warn the user clearly: "You are on protected branch `<name>`. Committing directly is discouraged."
- Ask for explicit confirmation before proceeding.
- Suggest creating a feature branch instead.

## 4. Generate Commit Message

If the user provided `$ARGUMENTS`, use that as guidance for the commit message (it may be a full message, a description of changes, or a type hint).

Analyze the staged diff to determine the appropriate commit message. The approach depends on the configured convention:

### Conventional Commits (`conventional`)
Format: `type(scope): description`

- **Determine type**: Analyze the diff content. New files/features = `feat`. Bug fixes = `fix`. Documentation only = `docs`. Formatting/whitespace = `style`. Code restructuring without behavior change = `refactor`. Performance improvement = `perf`. Test additions/changes = `test`. Build system/dependencies = `build`. CI config = `ci`. Maintenance/tooling = `chore`. Reverting a commit = `revert`.
- **Determine scope**: Identify the primary area affected (module, component, package). If `scopes` is configured, pick from that list. If `scope_required` is true, always include a scope. Otherwise, scope is optional.
- **Write description**: Imperative mood ("add" not "added"), lowercase start (if `case: lower`), no trailing period (if `no_trailing_period: true`), within `max_length` characters for the full subject line.
- **Breaking changes**: If the change is breaking, append `!` after the type/scope (if `exclamation_mark: true`) and include a `BREAKING CHANGE:` footer in the body (if `footer_required: true`).

### Angular Convention (`angular`)
Same as conventional but with stricter scope rules:
- Scope is more strongly encouraged.
- Scopes should match module/package names exactly.
- Types are identical to conventional.

### Gitmoji (`gitmoji`)
Format: `:emoji: description`

Map the determined type to the correct gitmoji:
- `feat` = `:sparkles:`, `fix` = `:bug:`, `docs` = `:memo:`, `style` = `:art:`, `refactor` = `:recycle:`, `perf` = `:zap:`, `test` = `:white_check_mark:`, `build` = `:hammer:`, `ci` = `:construction_worker:`, `chore` = `:wrench:`, `revert` = `:rewind:`

### Custom (`custom`)
Use the `custom_pattern` regex (with named groups: `type`, `scope`, `subject`) and `custom_description` to format the message.

### Freeform (`freeform`)
Write a natural language commit message. Still respect `max_length`. Use the recent commits above as a style guide.

**In all cases**: Consult the reference file at `${CLAUDE_SKILL_DIR}/references/commit-conventions.md` for detailed convention rules and examples.

## 5. Handle Pre-Checks

If `pre_checks.enabled` is true, run each command in `pre_checks.commands` before committing. If a required check fails, report the failure and stop. Do not commit.

## 6. Stage Files

When staging is needed:
- **Always prefer** `git add <specific-files>` with explicit file paths.
- **Never use** `git add -A` or `git add .` unless the user explicitly requests it.
- If the user said "commit everything" or "commit all changes", stage all modified and untracked files but list them first and confirm.

## 7. Create the Commit

Build the commit command:

```bash
git commit -m "$(cat <<'EOF'
<commit message here>
EOF
)"
```

Additional flags:
- If `signing.enabled` is true: add `--gpg-sign` (for gpg) or `-S` with the configured key.
- If a commit body is needed (breaking change footer, required body, or user-provided detail), use a multi-line message with the heredoc.

**IMPORTANT**: If a pre-commit hook fails, the commit did NOT happen. Fix the issue, re-stage if needed, and create a NEW commit. Never use `--amend` after a hook failure as that would modify a previous, unrelated commit.

## 8. Post-Commit

After a successful commit:
1. Run `git log --oneline -1` to show the created commit.
2. Run `git status --short` to show remaining working tree state.
3. Suggest next steps:
   - If there are more unstaged changes: "There are remaining changes. Would you like to create another commit?"
   - If the branch has no upstream: "Push this branch with `git push -u origin <branch>`?"
   - If the branch is ahead of remote: "Push to remote? Or create a PR?"

## 9. AI Attribution

If `ai_attribution` is `false` (the default):
- Do **NOT** include `Co-Authored-By` trailers.
- Do **NOT** include `Generated with` or `Generated by` lines.
- Do **NOT** add any mention of AI, Claude, or automated tooling in the commit message.

If `ai_attribution` is `true`:
- Add a `Co-Authored-By: Claude <noreply@anthropic.com>` trailer to the commit body.
