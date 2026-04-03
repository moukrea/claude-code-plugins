# Review Checklists Reference

Comprehensive checklists for each review mode. Use these as the basis for review,
combined with any user-defined checklist items from the `review.checklist` config.

---

## Default Checklist

Applied to every review regardless of which agents are enabled.

### Code Quality
- [ ] Code follows the project's established style and conventions
- [ ] No duplicated logic that should be extracted into shared functions
- [ ] Functions/methods have a single, clear responsibility
- [ ] No dead code, commented-out blocks, or TODO/FIXME left unresolved
- [ ] Magic numbers and strings are replaced with named constants

### Correctness
- [ ] Logic handles all expected input cases, including empty/null/zero
- [ ] Edge cases are accounted for (boundaries, overflow, off-by-one)
- [ ] State mutations are intentional and correctly ordered
- [ ] Concurrent/async operations handle race conditions
- [ ] Return values and error codes are checked at every call site

### Error Handling
- [ ] Errors are caught at appropriate boundaries, not swallowed silently
- [ ] Error messages are descriptive and include relevant context
- [ ] Cleanup/rollback occurs on failure (files closed, locks released, transactions rolled back)
- [ ] User-facing errors are safe (no stack traces or internal details exposed)

### Testing
- [ ] New logic has corresponding unit tests
- [ ] Edge cases and error paths are tested, not just happy paths
- [ ] Tests are deterministic (no reliance on timing, network, or random state)
- [ ] Test names clearly describe what is being verified
- [ ] No test pollution (shared mutable state between test cases)

### Documentation
- [ ] Public APIs have doc comments explaining purpose, parameters, and return values
- [ ] Non-obvious logic has inline comments explaining "why", not "what"
- [ ] Breaking changes are documented in changelog or migration guide
- [ ] README is updated if the feature changes user-facing behavior

### Naming
- [ ] Variable and function names accurately describe their purpose
- [ ] Naming is consistent with the rest of the codebase
- [ ] Abbreviations are avoided unless they are universally understood
- [ ] Boolean variables/functions read as questions (e.g., `isValid`, `hasPermission`)

### Complexity
- [ ] Functions are not excessively long (guideline: under 40 lines)
- [ ] Nesting depth does not exceed 3-4 levels (use early returns or extraction)
- [ ] Cyclomatic complexity is reasonable for the function's purpose
- [ ] Data transformations use clear, composable operations

---

## Security Checklist

Applied when `review.security` is `true`. Covers OWASP Top 10 and common vulnerability patterns.

### Injection (OWASP A03)
- [ ] All SQL queries use parameterized statements, never string concatenation
- [ ] OS command execution uses safe APIs with argument arrays, not shell interpolation
- [ ] LDAP, XPath, and template queries are parameterized
- [ ] ORM queries avoid raw SQL unless parameterized

### Broken Authentication (OWASP A07)
- [ ] Passwords are hashed with bcrypt/scrypt/argon2, never MD5/SHA1 alone
- [ ] Session tokens are generated with cryptographically secure randomness
- [ ] Authentication tokens have appropriate expiry and rotation
- [ ] Multi-factor authentication flows do not leak which factor failed

### Sensitive Data Exposure (OWASP A02)
- [ ] No secrets, API keys, tokens, or credentials in source code
- [ ] Sensitive data is encrypted at rest and in transit
- [ ] PII is not logged, cached, or stored unnecessarily
- [ ] HTTP responses include appropriate security headers (HSTS, no-sniff)

### Broken Access Control (OWASP A01)
- [ ] Authorization checks exist for every protected endpoint/resource
- [ ] Server-side enforcement, not client-side only
- [ ] IDOR vulnerabilities prevented (user cannot access others' resources by ID manipulation)
- [ ] Principle of least privilege applied to roles and permissions

### XSS and Output Encoding (OWASP A03)
- [ ] User input is escaped/encoded before rendering in HTML, JS, CSS, or URLs
- [ ] No direct use of `innerHTML`, `dangerouslySetInnerHTML`, or `v-html` with untrusted data
- [ ] Content Security Policy headers are configured
- [ ] Template engines use auto-escaping by default

### CSRF Protection
- [ ] State-changing requests require CSRF tokens
- [ ] SameSite cookie attribute is set appropriately
- [ ] Custom request headers validated for API endpoints

### Input Validation
- [ ] All external input is validated (type, length, range, format)
- [ ] Validation happens server-side, not only client-side
- [ ] File uploads are validated (type, size, content scanning)
- [ ] Redirect URLs are validated against an allowlist

### Security Configuration
- [ ] CORS is configured with specific origins, not wildcard in production
- [ ] Rate limiting is applied to authentication and sensitive endpoints
- [ ] Debug mode and verbose errors are disabled in production
- [ ] Dependencies are checked for known vulnerabilities

### Logging and Monitoring
- [ ] Security-relevant events are logged (auth failures, access denied, input validation)
- [ ] Logs do not contain sensitive data (passwords, tokens, PII)
- [ ] Log injection is prevented (user input in logs is sanitized)

---

## Performance Checklist

Applied when `review.performance` is `true`.

### Database and Queries
- [ ] No N+1 query patterns (use eager loading, joins, or batch fetching)
- [ ] Queries avoid `SELECT *` — only fetch needed columns
- [ ] New queries have appropriate indexes for WHERE/JOIN/ORDER BY clauses
- [ ] Pagination is implemented for endpoints that return lists
- [ ] Bulk operations use batch inserts/updates, not loops

### Caching
- [ ] Frequently accessed, rarely changing data uses caching
- [ ] Cache invalidation strategy is correct and complete
- [ ] Cache keys are specific enough to avoid stale data across users/contexts
- [ ] TTLs are appropriate for the data's freshness requirements

### Memory Management
- [ ] Large data sets are processed in streams or chunks, not loaded entirely into memory
- [ ] Resources are released promptly (connections, file handles, buffers)
- [ ] No memory leaks from event listeners, subscriptions, or closures that outlive their scope
- [ ] Object pools or reuse are considered for high-frequency allocations

### Async and Concurrency
- [ ] I/O operations use async/non-blocking APIs where available
- [ ] Independent async operations run in parallel (Promise.all, asyncio.gather, etc.)
- [ ] Connection pools are used for database and HTTP clients
- [ ] Thread/goroutine/task creation is bounded (no unbounded spawning)
- [ ] Locks are held for the minimum necessary duration

### Algorithmic Complexity
- [ ] No O(n^2) or worse algorithms on potentially large inputs
- [ ] Lookups use maps/sets/indexes instead of linear scans where appropriate
- [ ] Sorting is only done when necessary and uses efficient algorithms
- [ ] Regular expressions avoid catastrophic backtracking (no nested quantifiers)

### Frontend Performance
- [ ] Large dependencies are tree-shaken or loaded lazily
- [ ] Images and assets are optimized and appropriately sized
- [ ] Components avoid unnecessary re-renders (proper memoization, key usage)
- [ ] Bundle size impact is acceptable for new dependencies
- [ ] Network requests are batched or deduplicated where possible

---

## Custom Checklist Items

Users can define additional checklist items via the `review.checklist` config array
in `.git-master.yml`:

```yaml
review:
  checklist:
    - "Code follows project conventions and style"
    - "Error handling is appropriate and consistent"
    - "No hardcoded secrets or credentials"
    - "Tests adequately cover the changes"
    - "Documentation is updated if needed"
    - "Database migrations are reversible"        # Custom item
    - "Feature flags wrap new functionality"       # Custom item
    - "API changes are backward compatible"        # Custom item
```

Custom items are evaluated alongside the default checklist. They appear in the final
report under the same checklist results table.

### Language-Specific Rules

Define per-language rules in `review.language_rules`. Rules are matched by file
extension and added to the checklist for files of that language only.

```yaml
review:
  language_rules:
    python: ["Type hints on public functions", "No bare except clauses"]
    typescript: ["No 'any' in public APIs", "Strict null checks respected"]
    go: ["Errors wrapped with context (%w)", "Goroutine lifecycle managed"]
    rust: ["No unwrap/expect in library code", "Error types impl std::error::Error"]
```
