# Commit Convention Reference

## Conventional Commits v1.0.0

### Specification

The full format is:

```
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

**Subject line rules:**
- `type` is required and must be one of the allowed types.
- `scope` is a noun in parentheses describing the section of the codebase: `feat(parser):`, `fix(auth):`.
- `!` before the colon indicates a breaking change.
- `description` follows the colon and space. It is a short summary of the change.
- The entire subject line (type + scope + description) must fit within the configured `max_length` (default 72 characters).

**Body rules:**
- Separated from the subject by a blank line.
- Free-form text. Each line should not exceed `max_line_length` (default 100).
- Provides additional contextual information about the change.

**Footer rules:**
- Separated from the body by a blank line.
- Format: `token: value` or `token #value`.
- `BREAKING CHANGE: <description>` is a special footer indicating a breaking API change.
- Other common footers: `Refs: #123`, `Reviewed-by: Name`, `Closes #456`.

### Allowed Types

| Type | When to Use |
|---|---|
| `feat` | A new feature or capability is introduced |
| `fix` | A bug is corrected |
| `docs` | Documentation only changes (README, comments, JSDoc, docstrings) |
| `style` | Formatting, whitespace, semicolons — no logic change |
| `refactor` | Code restructuring that neither fixes a bug nor adds a feature |
| `perf` | A change that improves performance |
| `test` | Adding or correcting tests |
| `build` | Build system or external dependency changes (webpack, npm, pip) |
| `ci` | CI configuration changes (GitHub Actions, GitLab CI, Jenkins) |
| `chore` | Maintenance tasks that don't modify src or test files |
| `revert` | Reverts a previous commit |

### Examples

```
feat(auth): add OAuth2 login with Google provider
```

```
fix(parser): handle escaped quotes in CSV fields
```

```
docs: update installation instructions for Windows
```

```
feat(api)!: change authentication response format

BREAKING CHANGE: the /auth endpoint now returns a JWT token instead of a session cookie.
Clients must update their token handling logic.
```

---

## Angular Convention

The Angular convention is nearly identical to Conventional Commits with these distinctions:

- **Scopes are strongly encouraged** and should correspond to Angular modules, packages, or application layers.
- **Scope values** should be consistent within a project (e.g., `compiler`, `core`, `http`, `router`).
- The body **should** explain the motivation for the change and contrast with previous behavior.
- Footer `Closes #<issue>` is expected when a commit resolves an issue.

### Scope Guidelines

- Use the package or module name: `feat(forms):`, `fix(router):`.
- For cross-cutting concerns: `refactor(core):`, `chore(deps):`.
- Avoid overly broad scopes like `app` or `misc`.

### Examples

```
feat(forms): add async validator support for reactive forms
```

```
fix(router): resolve navigation guard promise rejection on redirect

The router was not properly catching rejected promises from navigation
guards when a redirect was issued during the beforeEach phase.

Closes #4521
```

```
refactor(compiler): extract template binding parser into separate module
```

```
perf(core): reduce change detection cycles for static views

Skip change detection for components marked as OnPush when no input
bindings have changed.
```

---

## Gitmoji

Gitmoji replaces the type prefix with an emoji. The description follows directly after a space.

### Emoji Mapping

| Emoji | Code | Equivalent Type | When to Use |
|---|---|---|---|
| :sparkles: | `:sparkles:` | feat | Introduce new features |
| :bug: | `:bug:` | fix | Fix a bug |
| :memo: | `:memo:` | docs | Add or update documentation |
| :art: | `:art:` | style | Improve structure/format of code |
| :recycle: | `:recycle:` | refactor | Refactor code |
| :zap: | `:zap:` | perf | Improve performance |
| :white_check_mark: | `:white_check_mark:` | test | Add or update tests |
| :hammer: | `:hammer:` | build | Build system changes |
| :construction_worker: | `:construction_worker:` | ci | CI/CD changes |
| :wrench: | `:wrench:` | chore | Configuration/tooling changes |
| :rewind: | `:rewind:` | revert | Revert changes |
| :lock: | `:lock:` | — | Fix security issues |
| :bookmark: | `:bookmark:` | — | Release/version tags |
| :rotating_light: | `:rotating_light:` | — | Fix compiler/linter warnings |
| :construction: | `:construction:` | — | Work in progress |
| :fire: | `:fire:` | — | Remove code or files |
| :truck: | `:truck:` | — | Move or rename resources |
| :boom: | `:boom:` | — | Introduce breaking changes |

### Examples

```
:sparkles: add dark mode toggle to settings page
```

```
:bug: fix race condition in WebSocket reconnection logic
```

```
:memo: document rate limiting configuration options
```

```
:boom: drop support for Node.js 14

BREAKING CHANGE: minimum required Node.js version is now 18 LTS.
```

---

## Choosing the Right Type

When the diff is ambiguous, use these heuristics:

1. **New file that adds functionality** -> `feat`
2. **New file that is a test** -> `test`
3. **New file that is documentation** -> `docs`
4. **Modified file that fixes incorrect behavior** -> `fix`
5. **Modified file that adds a new code path or capability** -> `feat`
6. **Modified file with only structural changes (rename, move, extract)** -> `refactor`
7. **Modified config file for build tools** -> `build`
8. **Modified CI pipeline file** -> `ci`
9. **Dependency version bumps** -> `build` (or `chore` if no build impact)
10. **Multiple types in one commit** -> Use the most significant type; suggest splitting if truly independent changes.
