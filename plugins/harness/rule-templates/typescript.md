---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# TypeScript Rules
- After major changes, verify types with `npx tsc --noEmit`
- Use LSP for go-to-definition and find-references when exploring code
- Prefer `interface` over `type` for public API definitions
- Replace `any` types with proper types when touching affected code
- Use strict null checks -- check for `undefined` and `null` explicitly
