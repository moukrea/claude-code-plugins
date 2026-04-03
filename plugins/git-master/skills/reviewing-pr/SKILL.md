---
name: reviewing-pr
description: >-
  Review a pull request or merge request with adversarial, security, and performance analysis.
  Trigger phrases: "review PR", "review this pull request", "code review", "check this PR",
  "review MR", "review merge request", "give feedback on PR", "review the changes",
  "review my code". Always use this skill when the user asks for any kind of code review
  on a PR, MR, or branch diff. Launches configurable review agents in parallel.
argument-hint: "[PR/MR number or 'local' for current branch diff]"
allowed-tools: Read, Bash, Grep, Glob
---

# Review PR/MR

## Dynamic Context

Review config:
```
!`cat "${GIT_MASTER_CONFIG_PATH:-/dev/null}" 2>/dev/null | jq '.review' 2>/dev/null || echo '{}'`
```

Provider:
```
!`echo "${GIT_MASTER_PROVIDER:-auto}"`
```

## Instructions

You are the git-master code review orchestrator. Follow these steps precisely.

### 1. Identify Target

- If `$ARGUMENTS` contains a PR/MR number (e.g., `123`, `#123`), fetch that PR via the detected provider.
- If `$ARGUMENTS` is `local` or empty, review the current branch diff against the base branch.
- Determine the provider CLI to use:
  - GitHub: `gh pr diff <number>`, `gh pr view <number> --json title,body,author,labels,changedFiles`
  - GitLab: `glab mr diff <number>`, `glab mr view <number>`
  - Local: `git diff $(git merge-base HEAD main)..HEAD` (detect default branch first)

### 2. Fetch Diff and Context

Run these commands to gather review material:

```bash
# For remote PR (GitHub example):
gh pr view <number> --json title,body,author,labels,additions,deletions,changedFiles
gh pr diff <number>

# For local review:
git log --oneline $(git merge-base HEAD <base>)..HEAD
git diff $(git merge-base HEAD <base>)..HEAD
git diff --stat $(git merge-base HEAD <base>)..HEAD
```

Also read the PR description/body if available -- it provides intent context.

### 3. Load Review Config

Extract these settings from the review config (shown in dynamic context above):

| Setting | Default | Purpose |
|---|---|---|
| `adversarial` | `true` | Launch adversarial reviewer agent |
| `security` | `true` | Launch security reviewer agent |
| `performance` | `false` | Launch performance reviewer agent |
| `checklist` | (see config) | Items to verify against changes |
| `confidence_threshold` | `80` | Only report findings above this score |
| `max_files_per_review` | `30` | Warn if PR exceeds this |
| `exclude_patterns` | lock files, minified, generated | Files to skip |
| `language_rules` | `{}` | Per-language additional checks |
| `security_patterns` | (see config) | Regex patterns for security issues |
| `performance_patterns` | (see config) | Regex patterns for performance issues |

### 4. Filter Files

Remove files from the review scope that match any `exclude_patterns` entry. Common exclusions:
- `*.lock`, `*.min.js`, `*.min.css`, `*.generated.*`
- `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`

Log how many files were excluded and how many remain.

### 5. Check File Count

If the number of changed files exceeds `max_files_per_review`:
- Warn the user that the PR is large and may benefit from splitting.
- Ask whether to proceed with all files or focus on a subset.
- Suggest logical groupings if possible (e.g., "frontend changes" vs "backend changes").

### 6. Run Review Checklist

Go through each item in the `checklist` config array against the actual changes. For each item, report:
- PASS: The changes satisfy this item.
- FAIL: The changes violate this item, with specific file:line references.
- N/A: This item does not apply to these changes.

### 7. Launch Review Agents

For each enabled review type, use the `Agent` tool to spawn a focused sub-agent **in parallel**:

- **adversarial-reviewer** (if `review.adversarial` is `true`):
  Prompt: "You are a devil's advocate code reviewer. Your job is to find flaws, edge cases, race conditions, incorrect assumptions, missing error handling, and logical errors. Be thorough and skeptical. For each finding, provide the file, line number, severity (Critical/High/Medium/Low), confidence (0-100), and a clear explanation. Here is the diff: <diff>"

- **security-reviewer** (if `review.security` is `true`):
  Prompt: "You are a security-focused code reviewer. Check for OWASP Top 10 vulnerabilities, injection risks, authentication/authorization flaws, secrets exposure, XSS, CSRF, insecure deserialization, and any security anti-patterns. For each finding, provide the file, line number, severity, confidence (0-100), CWE ID if applicable, and remediation advice. Here is the diff: <diff>"

- **performance-reviewer** (if `review.performance` is `true`):
  Prompt: "You are a performance-focused code reviewer. Check for N+1 queries, unnecessary allocations, missing indexes, unbounded loops, blocking I/O in async contexts, excessive re-renders, large bundle imports, and algorithmic complexity issues. For each finding, provide the file, line number, severity, confidence (0-100), estimated impact, and a suggested fix. Here is the diff: <diff>"

Pass the full diff and changed file list to each agent. Use the model config (`review.model` for standard, `review.adversarial_model` for adversarial).

### 8. Apply Language Rules

Check `language_rules` config for language-specific checks. For example:
```yaml
language_rules:
  python: ["Check type hints on public functions", "Verify no bare except clauses"]
  typescript: ["Ensure strict null checks", "No any types in public APIs"]
```

Apply the relevant rules based on the file extensions present in the diff.

### 9. Apply Pattern Matching

Scan the diff text against `security_patterns` and `performance_patterns`:

- For each pattern match, record the file, line, matched text, configured severity, and message.
- These are deterministic checks (regex-based) and always reported regardless of confidence threshold.

### 10. Aggregate Results

Combine findings from all sources:
1. Checklist results
2. Adversarial reviewer findings
3. Security reviewer findings
4. Performance reviewer findings
5. Language rule findings
6. Pattern match findings

Filter out any finding with confidence below `confidence_threshold` (except pattern matches, which are always included).

Group by severity: **Critical** > **High** > **Medium** > **Low**.

Deduplicate findings that overlap (same file, same line, similar issue).

### 11. Format Report

Output a structured markdown report:

```markdown
# Code Review: PR #<number> — <title>

## Summary
- **Files reviewed**: X of Y (Z excluded)
- **Findings**: C critical, H high, M medium, L low
- **Checklist**: X/Y passed

## Critical Findings
### [C1] <title> — `file.ts:42`
**Severity**: Critical | **Confidence**: 95% | **Source**: security-reviewer
<description and remediation>

## High Findings
...

## Medium Findings
...

## Low Findings
...

## Checklist Results
| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Code follows project conventions | PASS | |
| 2 | Error handling is appropriate | FAIL | Missing error handling in `api.ts:88` |

## Review Agents
| Agent | Findings | Duration |
|-------|----------|----------|
| adversarial | 3 | — |
| security | 1 | — |
| performance | 0 | — |
```

### 12. Post Review (Optional)

After presenting the report, ask the user if they want to:
1. **Post as PR comment**: Use `gm_provider pr-comment` to post the review summary.
2. **Approve**: Use `gm_provider pr-review --approve` (only if no critical/high findings).
3. **Request changes**: Use `gm_provider pr-review --request-changes` with findings summary.
4. **Do nothing**: Keep the review local only.

If the user confirms posting, use the appropriate provider operation:
```bash
# GitHub
gh pr review <number> --comment --body "<review summary>"

# GitLab
glab mr note <number> --message "<review summary>"
```
