---
name: configure
description: Configure git-pilot settings using natural language
---

# /configure

Perform the following steps to help the user configure git-pilot settings.

## Step 1: Read Config Schema

Use the reference table below to understand all available config keys:

| User Says | Config Change |
|-----------|--------------|
| "Make commit messages require a scope" | `commit.scopeRequired: true` |
| "Use feat/JIRA-123/description for branch names" | `branch.pattern: "{{type}}/{{ticket}}/{{description}}"` |
| "Auto-push after finishing work" | `remote.autoPush: true` |
| "Don't ask me about remote every time" | `remote.skipRemotePrompt: true` |
| "Commit after every 5 file changes" | `autoCommit.threshold: 5` |
| "Stop auto-committing" | `autoCommit.enabled: false` |
| "Always create draft PRs" | `mergeRequest.draft: true` |
| "Use underscores in branch names" | `branch.descriptionSeparator: "_", branch.descriptionCase: "snake"` |

## Step 2: Read Current Config

Read the current effective configuration merged from all three levels:

1. Plugin defaults (built-in)
2. Global config: `~/.claude/git-pilot.json`
3. Local config: `.claude/git-pilot.json`

Local settings override global settings, which override plugin defaults.

## Step 3: Present Current Settings

Present the current settings to the user in a readable format so they can see what is currently configured.

## Step 4: Ask What to Change

Ask the user what they would like to change. Wait for their response.

## Step 5: Map Natural Language to Config Keys

After the user describes the change in natural language, map it to the appropriate config keys using the reference table above and your understanding of the config schema.

## Step 6: Ask Global or Local

Ask the user whether the change should be:

- **Global** (`~/.claude/git-pilot.json`) — applies to all projects
- **Local** (`.claude/git-pilot.json`) — applies only to this project

## Step 7: Read Target Config File

Read the target config file. If it does not exist, start with an empty object `{}`.

## Step 8: Apply the Change

Apply the change using a deep merge, preserving all other existing settings. Do not overwrite unrelated keys.

## Step 9: Write the Updated Config File

Write the updated configuration back to the target config file.

## Step 10: Confirm the Change

Confirm the change to the user by showing what was changed and where the config file was written.
