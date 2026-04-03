# Common CI Failure Patterns and Fixes

## GitHub Actions

### Node/Runtime Version Mismatch
- **Pattern**: `Error: The current runner (ubuntu-22.04) was detected as self-hosted` or `node: /lib/x86_64-linux-gnu/libc.so.6: version 'GLIBC_2.28' not found`
- **Fix**: Pin the runner image version or use `actions/setup-node` with explicit version. Check `runs-on` and `node-version` fields.

### Action Version Deprecation
- **Pattern**: `Node.js 16 actions are deprecated` or `::warning::This action is using Node.js 12`
- **Fix**: Update action references to latest major version (e.g., `actions/checkout@v3` to `actions/checkout@v4`). Check the action's releases page.

### Cache Issues
- **Pattern**: `Cache not found for input keys` or `Failed to save cache` or stale dependencies after update
- **Fix**: Verify `hashFiles()` glob matches the lockfile. Use `actions/cache@v4`. Clear cache via `gh cache delete` or change the cache key prefix.

### Secrets Not Available in Fork PRs
- **Pattern**: Empty env var, `401 Unauthorized`, or `Error: Input required and not supplied: token`
- **Fix**: Use `pull_request_target` with caution, or make the step conditional: `if: github.event.pull_request.head.repo.full_name == github.repository`. Consider using OIDC tokens instead.

### GITHUB_TOKEN Permissions
- **Pattern**: `Resource not accessible by integration` or `403 Forbidden`
- **Fix**: Add explicit `permissions:` block to the workflow or job. Common needs: `contents: write`, `pull-requests: write`, `packages: read`.

### Workflow Syntax Errors
- **Pattern**: `.github/workflows/ci.yml: ...` with YAML parse errors
- **Fix**: Validate with `actionlint` locally. Common issues: unquoted `on:` triggers, bad indentation, expression syntax `${{ }}` typos.

## GitLab CI

### Runner/Executor Issues
- **Pattern**: `ERROR: Job failed (system failure): prepare environment` or `No matching runner found`
- **Fix**: Check runner tags match job tags. Verify runner is online in Settings > CI/CD > Runners. Check executor type (docker, shell, kubernetes).

### Docker-in-Docker (DinD)
- **Pattern**: `Cannot connect to the Docker daemon` or `dial tcp: lookup docker`
- **Fix**: Ensure `services: [docker:dind]` is declared. Set `DOCKER_HOST: tcp://docker:2376` and `DOCKER_TLS_CERTDIR: "/certs"`. Use `docker:24-dind` or newer.

### Artifact and Cache Expiry
- **Pattern**: Missing files from previous stage, `ERROR: Uploading artifacts... too large`
- **Fix**: Check `artifacts.expire_in` and `cache.policy`. Verify artifact paths match actual output locations. Use `dependencies:` or `needs:` to control artifact downloads.

### Variable Masking
- **Pattern**: `[MASKED]` in unexpected places or `ERROR: Variable ... is not available`
- **Fix**: Masked variables cannot be used in file paths or command names. Use a non-masked variable for non-secret values. Check protected/environment variable scopes.

### Pipeline Timeout
- **Pattern**: `ERROR: Job failed: execution took longer than 1h0m0s`
- **Fix**: Add `timeout:` at job level. Investigate why job is slow. Check for infinite loops, hanging network requests, or missing test timeouts.

## General Patterns

### Dependency Resolution Failures
- **Pattern**: `Could not resolve dependencies`, `ERESOLVE unable to resolve dependency tree`, `version solving failed`
- **Causes**: Yanked package, conflicting version constraints, registry outage, auth required for private registry
- **Fix**: Check lockfile is committed and up to date. Pin transitive dependencies. Use `--legacy-peer-deps` for npm (temporary). Check registry status pages.

### Lockfile Conflicts
- **Pattern**: `The lockfile needs to be updated` or `frozen lockfile` errors
- **Fix**: Regenerate lockfile locally, commit it. For CI, ensure install command matches lockfile mode (`npm ci`, `yarn --frozen-lockfile`, `pip install --require-hashes`).

### Flaky Tests

#### Timing-Dependent
- **Pattern**: Test passes locally, fails intermittently in CI. Involves `setTimeout`, `sleep`, `waitFor`, polling.
- **Fix**: Replace fixed delays with polling/retry. Increase timeouts for CI. Use `jest.useFakeTimers()` or equivalent.

#### Order-Dependent
- **Pattern**: Test fails only when run with full suite. Passes when run in isolation.
- **Fix**: Check for shared mutable state (global variables, database records, temp files). Add proper setup/teardown. Run with `--randomize` to detect.

#### External Service Dependency
- **Pattern**: `ECONNREFUSED`, `timeout`, `503 Service Unavailable` in test output
- **Fix**: Mock external services. Use test containers. Add retry logic to test helpers. Never rely on external APIs in CI.

### OOM Kills
- **Pattern**: `Killed`, `signal: killed`, `exit code 137`, `Container was OOMKilled`
- **Fix**: Increase runner memory or resource limits. Reduce parallelism (`--max-workers=2`). Check for memory leaks in tests. Split into multiple jobs.

### Disk Space Exhaustion
- **Pattern**: `No space left on device`, `ENOSPC`
- **Fix**: Clean up before build (`docker system prune`, remove unused artifacts). Use smaller base images. Add `actions/free-disk-space` step for GitHub. Check artifact sizes.

### Shell/Script Errors
- **Pattern**: `bash: command not found`, `Permission denied`, `set -e` causing silent failures
- **Fix**: Install required tools in CI. Add `chmod +x` for scripts. Use `set -euo pipefail` and handle errors explicitly.

### Environment Variable Issues
- **Pattern**: Empty variable expansion, `undefined` in config, wrong environment used
- **Fix**: Verify variable is set in the correct scope (repo, environment, job). Check for typos in variable names. Use `env:` block at the correct level.

## Diagnosis Shortcuts

| Error Code / Signal | Meaning                          |
|----------------------|----------------------------------|
| Exit 1               | General error (check stderr)    |
| Exit 2               | Shell builtin misuse            |
| Exit 126             | Permission denied (not executable) |
| Exit 127             | Command not found               |
| Exit 128+N           | Fatal signal N (137 = SIGKILL/OOM) |
| Exit 130             | SIGINT (Ctrl+C / cancelled)     |
| Exit 143             | SIGTERM (graceful shutdown)     |

## Quick Triage Checklist

1. Is this the first failure or a recurrence? Check last 5 runs.
2. Did any config files change in the failing commit? (`git diff HEAD~1 -- .github/ .gitlab-ci.yml`)
3. Is the failure in a specific job or all jobs?
4. Does the same commit pass on a different branch?
5. Did a dependency release recently? (`git diff HEAD~1 -- *lock*`)
6. Is the runner/infrastructure healthy? Check provider status page.
