---
name: reflect
description: After completing complex work, reflect on what could improve the
  project's configuration. May suggest updates to CLAUDE.md, rules, or skills.
  Use after major milestone completions.
user-invocable: false
context: fork
agent: architect
---

Review the work just completed and identify improvements:

1. Were there patterns Claude kept getting wrong that a CLAUDE.md rule could prevent?
2. Were there verification steps that should be automated via rules?
3. Were there conventions that should be documented?
4. Were there subagent configurations that could be improved?

Rules for suggestions:
- Only suggest changes that would prevent REAL problems observed during this work
- Do NOT add obvious or generic rules
- Do NOT add rules Claude already follows without being told
- Keep it concise -- every line in CLAUDE.md costs context

If you identify genuinely useful improvements, suggest them. Otherwise, do nothing.
