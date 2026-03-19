---
paths:
  - "**/*.test.*"
  - "**/*.spec.*"
  - "**/test/**"
  - "**/tests/**"
  - "**/__tests__/**"
---

# Testing Rules
- NEVER remove or weaken existing tests
- Tests should verify behavior, not implementation details
- Each test should be independent (no shared mutable state)
- Follow existing test patterns and conventions
- Include descriptive test names that explain the expected behavior
- Cover: happy path, error cases, edge cases, boundary conditions
