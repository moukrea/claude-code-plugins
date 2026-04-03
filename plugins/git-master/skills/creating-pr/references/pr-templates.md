# PR/MR Description Templates

## Placeholders

Use these placeholders in templates. They are populated automatically when `auto_populate: true`.

| Placeholder | Source | Description |
|---|---|---|
| `{SUMMARY}` | Synthesized from commits and diff | 1-3 sentence overview of the change |
| `{COMMITS}` | `git log --oneline base..HEAD` | Bulleted list of commit subjects |
| `{TEST_PLAN}` | Test files in diff or user input | How the changes were tested |
| `{BREAKING_CHANGES}` | Commit footers with `BREAKING CHANGE:` | List of breaking changes, if any |
| `{RELATED_ISSUES}` | Issue references in commit messages | Links to related issues/tickets |

---

## Default Template

Used when no template is configured or `description.template` is not set.

```markdown
## Summary
{SUMMARY}

## Changes
{COMMITS}

## Test plan
{TEST_PLAN}
```

### Example (rendered)

```markdown
## Summary
Add OAuth2 authentication with Google as a provider, replacing the legacy
session-based auth flow.

## Changes
- feat(auth): add OAuth2 login with Google provider
- feat(auth): add token refresh middleware
- fix(auth): handle expired refresh tokens gracefully
- test(auth): add integration tests for OAuth2 flow
- docs: update authentication section in README

## Test plan
- Added integration tests covering login, token refresh, and expiry.
- Manually tested the login flow against Google OAuth2 sandbox.
- Verified backward compatibility: existing sessions are migrated on first request.
```

---

## Minimal Template

For small changes or when brevity is preferred.

```markdown
{SUMMARY}
```

### Example (rendered)

```markdown
Fix race condition in WebSocket reconnection that caused duplicate event handlers
to accumulate after network interruptions.
```

---

## Detailed Template

For larger changes, breaking changes, or changes requiring extra context.

```markdown
## Summary
{SUMMARY}

## Changes
{COMMITS}

## Test plan
{TEST_PLAN}

## Breaking changes
{BREAKING_CHANGES}

## Screenshots
<!-- Add screenshots if this change affects UI -->

## Related issues
{RELATED_ISSUES}
```

### Example (rendered)

```markdown
## Summary
Migrate the authentication system from session cookies to JWT tokens. This
is a breaking change for all API consumers.

## Changes
- feat(api)!: replace session auth with JWT token auth
- feat(api): add /auth/refresh endpoint for token renewal
- fix(api): validate token expiry with clock skew tolerance
- chore(deps): add jsonwebtoken 9.0.0
- docs(api): update auth endpoints in OpenAPI spec

## Test plan
- Unit tests for token generation, validation, and refresh.
- Integration tests against the /auth, /auth/refresh, and protected endpoints.
- Load tested with 1000 concurrent token validations.
- Tested token expiry edge cases (clock skew, revoked tokens).

## Breaking changes
- The `/auth` endpoint now returns `{ "token": "...", "expires_in": 3600 }` instead of setting a session cookie.
- All API requests must include `Authorization: Bearer <token>` header.
- The `session_id` cookie is no longer issued or accepted.

## Screenshots
N/A (API-only change)

## Related issues
- Closes #892 — Migrate to stateless authentication
- Refs #901 — Token refresh mechanism design doc
```

---

## Template Selection Logic

1. If the user's config specifies `description.template`, use that template verbatim.
2. If no template is configured:
   - **1-2 commits, no breaking changes** -> Minimal template.
   - **3+ commits or breaking changes present** -> Default template.
   - **10+ commits, breaking changes, or cross-cutting changes** -> Detailed template.
3. The user can always override by providing their own description via `$ARGUMENTS` or when prompted.

## Section Requirements

When `description.required_sections` is set, the PR cannot be created until those sections have content:

- `summary` -> The `{SUMMARY}` placeholder must be filled.
- `test_plan` -> The `{TEST_PLAN}` placeholder must be filled. If no tests are evident in the diff, ask the user.
- `breaking_changes` -> Only required if breaking changes are detected.
- `related_issues` -> Only required if configured; ask the user for issue numbers.

If a required section cannot be auto-populated, prompt the user before creating the PR.
