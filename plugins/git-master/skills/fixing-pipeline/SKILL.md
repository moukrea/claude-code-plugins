---
name: fixing-pipeline
description: >-
  Diagnoses and fixes CI/CD pipeline failures. Trigger phrases: "fix pipeline",
  "fix CI", "fix the build", "fix failing tests", "CI is broken",
  "pipeline failed", "debug CI failure", "fix GitHub Actions", "fix GitLab CI",
  "why is the build failing", "fix the checks". Fetches logs, classifies the
  failure, identifies root cause, and applies targeted fixes.
argument-hint: "[PR number or job name]"
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
---

## Dynamic Context

Pipeline config:
```
${{cat "${GIT_MASTER_CONFIG_PATH:-/dev/null}" 2>/dev/null | jq '.pipeline' 2>/dev/null || echo '{}'}}
```

Provider:
```
${{echo "${GIT_MASTER_PROVIDER:-auto}"}}
```

Current branch:
```
${{git branch --show-current 2>/dev/null}}
```

## Instructions

Follow these steps in order. At each step, report what you find before moving on.

### 1. Identify the Failing Pipeline

Determine the target from `$ARGUMENTS` (PR number, job name, run ID) or fall back to the current branch.

- **GitHub**: `gh run list --branch <branch> --limit 5` to find recent runs, then `gh run view <id>` for details.
- **GitLab**: `glab ci status` or `glab ci list` for the current branch.
- **Gitea**: `tea ci ls` if available.

If no argument is given and no failing run is found on the current branch, check the default branch.

### 2. Fetch Failure Logs

Retrieve the full failure output:

- **GitHub Actions**: `gh run view <run-id> --log-failed` (focused) or `gh run view <run-id> --log` (full).
- **GitLab CI**: `glab ci trace <job-id>` or `glab ci view`.
- If the logs are too long, focus on the last 200 lines surrounding the first error.

Save the relevant log snippet for analysis.

### 3. Classify the Failure

Categorize into one of these types:

| Category         | Signals                                                        |
|------------------|----------------------------------------------------------------|
| **Build**        | Compilation errors, missing dependencies, build tool failures  |
| **Test**         | Assertion failures, timeouts, segfaults, exit code mismatches  |
| **Lint**         | Linter/formatter violations, type-check errors                 |
| **Infrastructure** | Docker pull failures, network timeouts, runner OOM, disk full |
| **Config**       | YAML syntax errors, missing env vars, invalid workflow syntax  |
| **Deployment**   | Deploy script failures, permission denied, rollback triggers   |

Report the classification and the key error lines.

### 4. Diagnose Root Cause

Analyze the logs to find the precise root cause. Check for:

- **Dependency issues**: Version mismatch, yanked package, lockfile conflict, registry unavailable.
- **Environment issues**: Missing env var or secret, wrong runtime version, Docker image tag changed.
- **Test failures**: Flaky test (check if it passed in recent runs), order-dependent test, external service dependency, timing issue.
- **Config errors**: YAML indentation, deprecated action version, renamed workflow key, missing permissions block.
- **Infrastructure**: OOM kill (check `dmesg` patterns in logs), disk space exhaustion, rate limiting.

Cross-reference with the project's CI configuration files:
- GitHub: Read `.github/workflows/*.yml`
- GitLab: Read `.gitlab-ci.yml`
- Also check `Dockerfile`, `docker-compose.yml`, `Makefile`, etc. as relevant.

### 5. Spawn Agent for Complex Failures

If the failure involves multiple interacting causes, spans several jobs, or requires deep analysis of test output, spawn the **pipeline-doctor** agent:

> Use `SendMessage` to the pipeline-doctor agent with:
> - The failure logs (trimmed to relevant sections)
> - The CI config file contents
> - The failure classification from step 3
> - Any dependency files (package.json, requirements.txt, go.mod, etc.)

Wait for the agent's diagnosis before proceeding.

### 6. Propose the Fix

Present a clear summary:

```
FAILURE:  <one-line description of what failed>
CATEGORY: <Build | Test | Lint | Infrastructure | Config | Deployment>
ROOT CAUSE: <specific cause>
FIX: <what needs to change and why>
```

Show the exact file(s) and line(s) that need to change. If there are multiple possible fixes, list them ranked by confidence.

### 7. Apply the Fix

Ask the user for confirmation before making changes. Then:

1. Make the code change.
2. Verify the fix makes sense locally if possible (e.g., run the failing test, check syntax).
3. Suggest committing with an appropriate message using the **committing** skill. Example: `fix(ci): pin node version to 20.x in build workflow`.

### 8. Retry the Pipeline

After the fix is committed and pushed, offer to re-trigger:

- **GitHub**: `gh run rerun <run-id>` or `gh run rerun <run-id> --failed` (retry only failed jobs).
- **GitLab**: `glab ci retry <job-id>`.

If the pipeline config includes `ignored_checks`, mention which checks are being skipped.

## Important Notes

- Never expose secrets or tokens found in CI logs. Redact them immediately.
- If the failure is in a fork PR, note that secrets are intentionally unavailable and the fix may require a different approach.
- For flaky tests, suggest both an immediate fix (retry/skip) and a long-term fix (stabilize the test).
- Check `pipeline.max_auto_fix_attempts` in config; warn if approaching the limit.
