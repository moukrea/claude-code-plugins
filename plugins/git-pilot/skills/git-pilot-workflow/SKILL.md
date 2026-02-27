---
name: git-pilot-workflow
description: "USE THIS SKILL WHEN the user asks to write code, fix a bug, implement a feature, refactor, add tests, update documentation, or do any work that results in file changes in a git repository. This skill governs the git workflow throughout the entire session -- branch creation, commit formatting, push prompts, and session-end procedures. Trigger on any coding or development task. Even if the user does not mention git, if the task involves code changes, still use this skill."
---

# git-pilot Workflow

This skill activates the git-pilot behavioral contract defined in CLAUDE.md.
All rules are in CLAUDE.md -- this skill serves as a trigger to ensure the
contract is loaded.

## Quick Reference

1. Never work on default branch -- use /branch first
2. Follow commit format -- type(scope): description
3. After each commit -- prompt to push
4. On session end -- use /finish
5. Act on [git-pilot] hook context per CLAUDE.md Rule 10

For detailed rules, see CLAUDE.md.
