---
name: requirements-interview
description: Interview the user to gather detailed requirements for underspecified
  tasks. Uses AskUserQuestion for structured gathering. Use when a task is too vague
  for its complexity level.
user-invocable: false
---

The user has requested: $ARGUMENTS

This request needs clarification before implementation. Use the AskUserQuestion
tool to interview the user about:

1. Technical constraints (language, framework, existing patterns to follow)
2. Scope boundaries (what's in/out of scope)
3. Edge cases they've considered
4. Acceptance criteria (how will we know it's done?)
5. Priority (which parts are most important?)

Ask ONE question at a time. Keep questions concrete and offer choices where
possible. Stop interviewing when you have enough detail to create a clear
task decomposition.
