---
paths:
  - "**/migrations/**"
  - "**/*.sql"
  - "**/schema*"
  - "**/models/**"
---

# Database Rules
- NEVER drop tables or columns without explicit user confirmation
- Always create reversible migrations (both up and down)
- Test migrations on a copy before applying to production
- Review index impact on large tables
- Check for N+1 query patterns in ORM code
