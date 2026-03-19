---
name: harness-init
description: Initialize the harness for a project. Detects project type, creates
  path-specific rules, and adds harness instructions to CLAUDE.md. Run once per
  project to set up enhanced workflows.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

Initialize the harness for this project:

1. **Detect project type:**
   - Check for package.json, Cargo.toml, go.mod, pyproject.toml, Makefile, etc.
   - Identify languages used (by file extensions)
   - Identify frameworks (by dependencies)
   - Detect monorepo structure (multiple package managers at different depths)

2. **Create path-specific rules:**
   - For each detected language, create `.claude/rules/<language>.md` using the
     templates in this skill's directory at `${CLAUDE_SKILL_DIR}/../../rule-templates/`
   - Only create rules for languages actually present in the project

3. **Add harness section to CLAUDE.md** (if CLAUDE.md exists, append; if not, create):
   Use the template at `${CLAUDE_SKILL_DIR}/templates/claude-md-section.md`

4. **Detect and record verification commands:**
   - Test command (npm test, cargo test, pytest, go test, make test)
   - Lint command (eslint, ruff, clippy, golangci-lint)
   - Build command (npm run build, cargo build, go build, make)
   - Type check command (tsc --noEmit, mypy, cargo check)

5. **Set up shared task list** for multi-session continuity:
   - Suggest setting CLAUDE_CODE_TASK_LIST_ID in .claude/settings.local.json env

6. **Report what was set up** concisely to the user.

Do NOT create any files in a `.harness/` directory. Use native Claude Code
features (task list, auto memory, CLAUDE.md, .claude/rules/) for everything.
