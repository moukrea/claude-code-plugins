---
name: branch
description: Create a new branch using the configured naming pattern
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
