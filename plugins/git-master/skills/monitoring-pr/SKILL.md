---
name: monitoring-pr
description: >-
  Check the status of a pull request or merge request including pipeline, reviews, and merge readiness.
  Trigger phrases: "check PR status", "monitor PR", "PR status", "is the pipeline passing",
  "CI status", "check my PR", "any review comments", "what's happening with my PR",
  "check merge request", "MR status". Always use this skill when the user wants to know the
  current state of a PR/MR or its CI pipeline. Shows a unified dashboard.
argument-hint: "[PR/MR number]"
allowed-tools: Read, Bash, Grep
---

# Monitor PR/MR Status

## Dynamic Context

Provider:
```
!`echo "${GIT_MASTER_PROVIDER:-auto}"`
```

Current branch:
```
!`git branch --show-current 2>/dev/null`
```

## Instructions

You are the git-master PR/MR monitoring agent. Gather all status information and present a clear, actionable dashboard.

### 1. Identify Target PR

Determine which PR/MR to monitor:

- If `$ARGUMENTS` contains a number, use that as the PR/MR identifier.
- If `$ARGUMENTS` is empty, find the PR/MR associated with the current branch:
  ```bash
  # GitHub
  gh pr view --json number,url --jq '.number' 2>/dev/null

  # GitLab
  glab mr view --output json 2>/dev/null | jq '.iid'
  ```
- If no PR exists for the current branch, inform the user and suggest creating one.

### 2. Gather Status

Run the following commands **in parallel** to collect all status data. Adapt commands based on the detected provider.

#### PR Metadata

```bash
# GitHub
gh pr view <number> --json number,title,state,author,createdAt,url,headRefName,baseRefName,additions,deletions,changedFiles,body,isDraft,mergeable,labels

# GitLab
glab mr view <number> --output json
```

#### Pipeline / CI Status

```bash
# GitHub — check status of all CI checks
gh pr checks <number> --json name,state,conclusion,url

# GitHub — workflow runs on the branch
gh run list --branch <head-branch> --limit 5 --json name,status,conclusion,url,createdAt

# GitLab
glab ci status --output json
```

#### Review Status

```bash
# GitHub — reviews and review requests
gh pr view <number> --json reviews,reviewRequests,reviewDecision
gh api repos/<owner>/<repo>/pulls/<number>/reviews --jq '.[] | {user: .user.login, state: .state, submitted_at: .submitted_at}'

# GitLab
glab mr view <number> --output json   # includes approvals and reviewers
```

#### Merge Readiness

```bash
# GitHub
gh pr view <number> --json mergeable,mergeStateStatus,statusCheckRollup

# Check if branch is up to date with base
git fetch origin <base-branch> 2>/dev/null
git log --oneline origin/<base-branch>..origin/<head-branch> --right-only 2>/dev/null | wc -l
```

#### Recent Comments

```bash
# GitHub
gh api repos/<owner>/<repo>/issues/<number>/comments --jq '.[-5:] | .[] | {author: .user.login, created: .created_at, body: .body[:120]}'

# GitLab
glab api projects/<id>/merge_requests/<number>/notes --jq '.[-5:] | .[] | {author: .author.username, created: .created_at, body: .body[:120]}'
```

### 3. Format Dashboard

Present all gathered information in a structured dashboard:

```markdown
# PR #<number>: <title>

**Author**: @<author> | **Branch**: `<head>` -> `<base>` | **State**: <open/draft/merged/closed>
**Created**: <date> | **URL**: <url>
**Size**: +<additions> / -<deletions> across <changedFiles> files

---

## Pipeline Status

| Check | Status | Conclusion | Link |
|-------|--------|------------|------|
| build | completed | success | [link] |
| test  | completed | success | [link] |
| lint  | in_progress | — | [link] |

**Overall**: X/Y checks passed, Z pending

## Review Status

| Reviewer | Status | Date |
|----------|--------|------|
| @alice | APPROVED | 2024-01-15 |
| @bob | CHANGES_REQUESTED | 2024-01-14 |
| @carol | PENDING | — |

**Review decision**: Changes requested (1 approval, 1 change request, 1 pending)

## Merge Readiness

- [x] Pipeline passing
- [x] Required approvals met (2/2)
- [ ] No requested changes outstanding
- [x] No merge conflicts
- [ ] Up to date with base branch (3 commits behind)
- [x] Branch protection rules satisfied

## Recent Activity

| Author | Time | Comment |
|--------|------|---------|
| @bob | 2h ago | "The error handling in api.ts needs..." |
| @alice | 5h ago | "LGTM, nice refactor" |
```

### 4. Suggest Next Steps

Based on the current state, provide actionable suggestions. Only include relevant items:

**If pipeline is failing:**
> Pipeline check `<name>` is failing. Run `/git-master:fixing-pipeline` to diagnose and fix.

**If changes were requested:**
> @<reviewer> requested changes. Address their feedback, push new commits, then request re-review.

**If behind base branch:**
> Branch is <N> commits behind `<base>`. Rebase with:
> ```
> git fetch origin && git rebase origin/<base>
> ```

**If all checks pass and approved:**
> PR is ready to merge. Merge with:
> ```bash
> # GitHub
> gh pr merge <number> --squash --delete-branch
> # GitLab
> glab mr merge <number> --squash --remove-source-branch
> ```

**If PR is in draft:**
> PR is still in draft. When ready, mark as ready for review:
> ```bash
> gh pr ready <number>
> ```

**If no reviewers assigned:**
> No reviewers assigned. Add reviewers:
> ```bash
> gh pr edit <number> --add-reviewer <username>
> ```

**If merge conflicts:**
> Merge conflicts detected. Resolve locally:
> ```bash
> git fetch origin && git rebase origin/<base>
> # Resolve conflicts, then:
> git push --force-with-lease
> ```
