---
name: creating-pr
description: >-
  Create pull requests (GitHub) or merge requests (GitLab) with auto-generated
  titles, descriptions, labels, and reviewers. Use when the user says:
  "create PR", "create a PR", "open pull request", "create merge request",
  "create MR", "make a PR", "open PR", "submit PR", "push and create PR",
  or asks to send changes for review. Supports GitHub (gh) and GitLab (glab).
argument-hint: "[optional PR title or target branch]"
allowed-tools: Read, Bash, Grep, Glob
---

# Dynamic Context

**PR config:**
!`cat "${GIT_MASTER_CONFIG_PATH:-/dev/null}" 2>/dev/null | jq '.pr' 2>/dev/null || echo "no config"`

**Branch config:**
!`cat "${GIT_MASTER_CONFIG_PATH:-/dev/null}" 2>/dev/null | jq '.branch' 2>/dev/null || echo "no config"`

**Provider:**
!`echo "${GIT_MASTER_PROVIDER:-auto}"`

**Current branch:**
!`git branch --show-current 2>/dev/null`

**Default remote branch:**
!`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main"`

**Commits ahead of base:**
!`git log --oneline "$(git merge-base HEAD origin/$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main) 2>/dev/null || echo HEAD~10)..HEAD" 2>/dev/null`

**Working tree status:**
!`git status --short 2>/dev/null`

---

# Create PR/MR Workflow

Follow these steps in order. Do NOT skip steps.

## 1. Read Configuration and Detect Provider

Parse the injected PR and branch config above. Extract these settings (use defaults when missing):

| Setting | Default |
|---|---|
| `title.convention` | `inherit` |
| `title.max_length` | `72` |
| `description.template` | (see reference) |
| `description.required_sections` | `[summary, test_plan]` |
| `auto_populate` | `true` |
| `draft` | `false` |
| `labels` | `[]` |
| `auto_labels` | `true` |
| `label_rules` | (see config) |
| `size_labels.enabled` | `true` |
| `reviewers.auto_assign` | `true` |
| `reviewers.rules` | `[]` |
| `reviewers.fallback` | `[]` |
| `assignees` | `[]` |
| `target_branch` | `""` (auto-detect) |

**Detect provider**: Check the injected provider value. If `auto`, determine from the git remote URL:
- `github.com` -> GitHub, use `gh`
- `gitlab.com` -> GitLab, use `glab`
- Otherwise, try `gh` first, then `glab`

Verify the CLI tool is installed and authenticated:
- GitHub: `gh auth status`
- GitLab: `glab auth status`

If not authenticated, tell the user and stop.

## 2. Validate Readiness

Check these conditions before proceeding:

### Protected Branch
Compare the current branch against `branch.protected` (default: `main`, `master`, `develop`). If the current branch IS a protected branch, tell the user: "You are on `<branch>` which is a protected branch. You cannot create a PR from a protected branch to itself. Please create a feature branch first." Then stop.

### Commits Ahead
Check the injected "commits ahead" output. If there are zero commits ahead of the base branch, tell the user: "No commits ahead of `<base>`. Nothing to create a PR for." Then stop.

### Uncommitted Changes
Check the injected working tree status. If there are uncommitted changes:
- Warn the user: "You have uncommitted changes."
- List them.
- Ask: "Would you like to commit them first before creating the PR?"
- If yes, invoke the committing workflow (or guide the user through it).
- If no, proceed with only the committed changes.

### Existing PR
Check if a PR already exists for this branch:
- GitHub: `gh pr view --json url,state 2>/dev/null`
- GitLab: `glab mr view 2>/dev/null`

If a PR already exists and is open, show the URL and ask: "A PR already exists for this branch. Would you like to update it instead?" Do not create a duplicate.

## 3. Push Branch

Check if the branch has an upstream:
```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
```

If no upstream exists, push with tracking:
```bash
git push -u origin <current-branch>
```

If an upstream exists but there are unpushed commits, push:
```bash
git push
```

## 4. Determine Target Branch

Use `target_branch` from config if set. Otherwise, use the default remote branch (from dynamic context above, typically `main` or `master`).

If `$ARGUMENTS` contains what looks like a branch name (no spaces, matches an existing remote branch), use it as the target.

## 5. Generate PR Title

Based on the `title.convention`:

### `inherit` (from commit convention)
- If there is a single commit, use its subject line as the PR title.
- If there are multiple commits, derive a title that summarizes the overall change. Look at the commit types: if all are the same type, use that type. Otherwise, use the most significant type.
- Follow the same formatting rules as the commit convention (conventional, angular, gitmoji, etc.).

### `conventional`
Format the title as `type(scope): description`, following conventional commit rules regardless of the commit convention.

### `custom`
Use the `title.custom_pattern` to format the title.

### `freeform`
Write a clear, concise title. No prefix required.

**In all cases**: Respect `title.max_length`. If `$ARGUMENTS` looks like a title (contains spaces, descriptive text), use it as the title or as guidance.

## 6. Generate PR Description

Use the configured `description.template`. If `auto_populate` is true, fill in automatically:

- **{COMMITS}**: Render from the git log of commits ahead of base. Format as a bulleted list.
- **{SUMMARY}**: Synthesize from the commit messages and diff. Write 1-3 sentences explaining the purpose.
- **{TEST_PLAN}**: If discernible from commits (e.g., test files were added/modified), describe the testing. Otherwise, ask the user.
- **{BREAKING_CHANGES}**: Scan commit messages for `BREAKING CHANGE:` or `!` markers. List them if found.
- **{RELATED_ISSUES}**: Scan commit messages for issue references (`#123`, `PROJ-456`). List them if found.

If `required_sections` includes sections that cannot be auto-populated, ask the user to provide them before creating the PR.

Consult `${CLAUDE_SKILL_DIR}/references/pr-templates.md` for template definitions and formatting.

## 7. Apply Labels

### Static Labels
Always apply labels from the `labels` list in config.

### Auto Labels (if `auto_labels: true`)
Determine changed files:
```bash
git diff --name-only origin/<base>..HEAD
```

Match changed file paths against `label_rules`:
- Each rule has a `pattern` (glob) and `labels` (list).
- If any changed file matches the pattern, add those labels.
- Collect all matching labels into a deduplicated list.

### Size Labels (if `size_labels.enabled: true`)
Count total lines changed:
```bash
git diff --stat origin/<base>..HEAD | tail -1
```

Map to size label based on thresholds:
- 0 to `xs` (10) = `size/XS`
- `xs` to `s` (50) = `size/S`
- `s` to `m` (200) = `size/M`
- `m` to `l` (500) = `size/L`
- `l` to `xl` (1000) = `size/XL`
- above `xl` = `size/XXL`

**Note**: Only apply labels that actually exist in the repository. If a label does not exist:
- GitHub: `gh label create <name>` to create it, or skip with a warning.
- GitLab: Skip with a warning (labels must be pre-created).

## 8. Assign Reviewers

If `reviewers.auto_assign` is true:

1. Match changed files against `reviewers.rules` (each rule has a `pattern`, `reviewers` list, and `required` count).
2. Collect all matching reviewers.
3. If no rules matched, use `reviewers.fallback`.
4. Apply `team_reviewers` if configured.

If no reviewers are configured at all, skip this step silently.

## 9. Create the PR/MR

### GitHub
```bash
gh pr create \
  --title "<title>" \
  --body "$(cat <<'EOF'
<description body>
EOF
)" \
  --base "<target-branch>" \
  [--draft] \
  [--label "<label1>" --label "<label2>"] \
  [--reviewer "<user1>" --reviewer "<user2>"] \
  [--assignee "<user>"]
```

### GitLab
```bash
glab mr create \
  --title "<title>" \
  --description "$(cat <<'EOF'
<description body>
EOF
)" \
  --target-branch "<target-branch>" \
  [--draft] \
  [--label "<label1>" --label "<label2>"] \
  [--reviewer "<user1>" --reviewer "<user2>"] \
  [--assignee "<user>"]
```

If `draft` is true in config, always add the draft flag unless the user explicitly says "not a draft" or "ready for review".

## 10. Report Result

After successful creation:

1. **Show the PR/MR URL** prominently.
2. **List applied metadata**: labels, reviewers, assignees, draft status.
3. **Mention target branch**: "Targeting `<base>` from `<branch>`."
4. **If size label was applied**: mention the PR size for awareness.
5. **Suggest next steps**:
   - "Monitor CI status with `/monitoring-pr`"
   - "View the PR at <url>"
