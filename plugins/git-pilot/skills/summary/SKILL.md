---
name: summary
description: Show a summary of work done on the current branch
---

# /summary

Perform the following steps to generate and display a summary of work done on the current branch.

## Step 1: Determine Branches

1. Get the default branch from `git.defaultBranch` in the config.
2. Get the current branch: run `git branch --show-current`.
3. If the current branch equals the default branch, check the reflog for the branch that was last checked out.

## Step 2: Collect Data

Gather the following information:

1. **Commit log** (if `summary.includeCommitLog` is `true`): run `git log <defaultBranch>..HEAD --oneline --no-decorate`
2. **File stats** (if `summary.includeFileChanges` is `true`): run `git diff --stat <defaultBranch>...HEAD`
3. **Full diff** (if `summary.includeDiff` is `true`): run `git diff <defaultBranch>...HEAD`

## Step 3: Handle No Commits

If no commits are found between the current branch and the default branch, output:

```
[git-pilot] No commits on this branch relative to '<defaultBranch>'. Nothing to summarize.
```

Then stop.

## Step 4: Format the Summary

Format the output based on `summary.format`:

### Markdown format (`"markdown"`):

```markdown
## Work Summary: <branchName>

### Commits (<count>)
- <hash> <message>
- ...

### Files Changed (<count>)
<git diff --stat output>
```

### Plain format (`"plain"`):

```
Work Summary: <branchName>

Commits (<count>):
  <hash> <message>
  ...

Files Changed (<count>):
  <git diff --stat output>
```

## Step 5: Present the Summary

Present the formatted summary to the user.

## Config Key Reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `summary.includeFileChanges` | boolean | `true` | Include file change stats in summary. |
| `summary.includeDiff` | boolean | `false` | Include full diff in summary. |
| `summary.includeCommitLog` | boolean | `true` | Include commit log in summary. |
| `summary.format` | string | `"markdown"` | One of `"markdown"`, `"plain"`. |
