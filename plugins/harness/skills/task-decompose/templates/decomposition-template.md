# Decomposition Template

## Unit Template
```json
{
  "id": "unit-NNN",
  "description": "One-sentence description of the work",
  "files": ["src/path/file.ts"],
  "acceptance_criteria": [
    "Specific testable criterion 1",
    "Specific testable criterion 2"
  ],
  "depends_on": [],
  "verification": "npm test -- --grep 'pattern'"
}
```

## Common Decomposition Patterns

### Feature Implementation
1. Data model / types / interfaces
2. Business logic / service layer
3. API endpoint / controller
4. UI component
5. Tests for each layer
6. Integration test

### Refactoring
1. Create new abstraction / interface
2. Implement new version
3. Migrate consumers one at a time
4. Remove old implementation
5. Update tests

### Migration
1. Create migration script
2. Update data access layer
3. Update dependent services
4. Run migration
5. Verify data integrity
