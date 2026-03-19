---
name: spec-ingest
description: Ingest a specification document (PRD, design doc, requirements) and
  decompose it into granular feature units with verification criteria. Produces
  50-200+ features for comprehensive coverage.
disable-model-invocation: true
context: fork
agent: architect
---

Ingest this specification and decompose it: $ARGUMENTS

ultrathink about the feature decomposition.

Process:
1. Read the entire specification document
2. Extract EVERY discrete feature, requirement, and acceptance criterion
3. Be extremely granular -- Anthropic research shows 200+ features prevents
   premature completion declarations
4. For each feature, define:
   - Category (functional, UI, API, data, integration, non-functional)
   - Description (specific, testable)
   - Verification steps (how to confirm it works)
   - Priority (1 = must-have, 2 = important, 3 = nice-to-have)
   - Dependencies (which features must come first)
5. Group features into modules
6. Create tasks via TaskCreate for each feature
7. Present a summary: total features, module breakdown, suggested implementation order

CRITICAL: Features MUST be in a format that can be verified. Each feature
should describe observable behavior, not internal implementation details.

For the feature schema, see [schema](templates/feature-schema.json).
