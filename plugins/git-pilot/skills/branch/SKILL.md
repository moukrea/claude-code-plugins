---
name: branch
user-invocable: true
description: "USE THIS SKILL WHEN you are about to start making code changes and you are on the default branch, when the user describes a new feature or fix, or when starting any implementation work. Creates a new branch using the configured naming pattern so work never happens directly on the default branch. Trigger on: user requests a feature, bug fix, refactor, or any code change; user says 'let's work on X'; you detect you are on main/master/default branch before writing code; the git-pilot-workflow skill directs you to branch. Even if the user doesn't explicitly ask for a branch, still use this skill before making changes on the default branch."
---

# /branch

Perform the following steps to create a new branch using the configured naming pattern.

## Step 1: Read Branch Configuration

Read the current branch configuration from the effective config:

- `branch.pattern` (default: `"{{type}}/{{description}}"`)
- `branch.types` (default: `["feat", "fix", "refactor", "docs", "test", "chore", "style", "perf", "build", "ci"]`)
- `branch.descriptionSeparator` (default: `"-"`)
- `branch.descriptionCase` (default: `"kebab"`)
- `branch.maxLength` (default: `72`)

## Step 2: Prompt the User

Prompt the user for the following information:

1. **Type**: Ask the user to select from `branch.types` (`feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `perf`, `build`, `ci`).
2. **Description**: Ask for a short description of the work.
3. **Scope**: Only prompt if `branch.pattern` includes `{{scope}}`.
4. **Ticket**: Only prompt if `branch.pattern` includes `{{ticket}}`.

## Step 3: Validate the Branch Name

Validate the resulting branch name:

1. Ensure it matches the `branch.pattern` template after substitution.
2. Ensure the description uses the configured `branch.descriptionCase`:
   - `"kebab"`: lowercase words separated by hyphens (e.g., `add-user-auth`)
   - `"snake"`: lowercase words separated by underscores (e.g., `add_user_auth`)
   - `"camel"`: camelCase (e.g., `addUserAuth`)
3. Ensure the description uses the configured `branch.descriptionSeparator` (e.g., `"-"`, `"_"`).
4. Ensure the total branch name length is <= `branch.maxLength` (default: 72).

If validation fails, inform the user and prompt again.

## Step 4: Create the Branch

Create and switch to the new branch:

```
git switch -c <branch-name>
```

## Step 5: Record Branch Context

After creating the branch, note the base branch (the branch you were on before switching)
and the branch purpose (derived from the description). These are used for unrelated work
detection and drift checks.
