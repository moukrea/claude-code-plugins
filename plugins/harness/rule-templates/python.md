---
paths:
  - "**/*.py"
---

# Python Rules
- After major changes, run type checking with `mypy` (if configured)
- Use `ruff` for linting (if available), otherwise `flake8`
- Follow existing code style (check for black/ruff formatting)
- Use type hints for function signatures
- Prefer pathlib over os.path for file operations
