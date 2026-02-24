# git-pilot — Git Workflow Guidelines

## Branch Workflow
- Always work on a feature branch, never directly on the default branch
- Name branches using the configured pattern
- Check .claude/git-pilot.json (local) or ~/.claude/git-pilot.json (global) for current config
- Before making changes, ensure you are on the correct branch

## Commit Guidelines
- Follow the configured commit message format
- Do NOT include Co-Authored-By, Generated with, or any AI attribution lines in commits
- Keep commit subjects under the configured max length
- Use imperative mood in commit descriptions ("add" not "added")
- One logical change per commit

## When Finishing Work
- Commit all remaining changes before ending the session
- Check if the user wants to push to remote
- Check if the user wants to create a merge/pull request

## Configuration
- Users can change git-pilot settings by asking in natural language
- Global config: ~/.claude/git-pilot.json
- Local config: .claude/git-pilot.json
- Local settings override global settings
- When changing config, ask whether the change should be global or project-specific
