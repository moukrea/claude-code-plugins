#!/usr/bin/env bash
# provider-github.sh — GitHub provider implementation.
# Primary: gh CLI. Fallback: GitHub REST API via curl.
# Meant to be sourced, not executed directly.

# Guard against double-sourcing.
[[ -n "${_GM_PROVIDER_GITHUB_LOADED:-}" ]] && return 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Check that gh is authenticated. Returns 0 if OK, 3 if auth needed.
_github_check_auth() {
  if ! command -v gh &>/dev/null; then
    echo '{"error":"gh CLI not found"}' >&2
    return 1
  fi
  if ! gh auth status &>/dev/null; then
    echo '{"error":"gh CLI not authenticated. Run: gh auth login"}' >&2
    return 3
  fi
  return 0
}

# Build the GitHub API base URL for curl fallback.
# Uses GITHUB_API_URL if set, otherwise https://api.github.com.
_github_api_url() {
  printf '%s' "${GITHUB_API_URL:-https://api.github.com}"
}

# Get an auth token for curl fallback.
_github_token() {
  local token_env
  token_env="$(gm_config_get 'provider.token_env' 2>/dev/null || echo "")"
  if [[ -n "$token_env" ]]; then
    printf '%s' "${!token_env:-}"
    return
  fi
  # Try gh as token source.
  if command -v gh &>/dev/null; then
    gh auth token 2>/dev/null || true
    return
  fi
  # Common environment variables.
  printf '%s' "${GITHUB_TOKEN:-${GH_TOKEN:-}}"
}

# Authenticated curl wrapper for the GitHub REST API.
_github_curl() {
  local method="$1" endpoint="$2"
  shift 2
  local token
  token="$(_github_token)"
  if [[ -z "$token" ]]; then
    echo '{"error":"no GitHub token available for API fallback"}' >&2
    return 3
  fi
  local url
  url="$(_github_api_url)${endpoint}"
  curl -sf -X "$method" \
    -H "Authorization: token $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@" "$url"
}

# ---------------------------------------------------------------------------
# PR operations
# ---------------------------------------------------------------------------

_github_pr_create() {
  _github_check_auth || return $?

  local title="" body="" draft="" base=""
  local -a labels=() reviewers=() extra_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)    title="$2";    shift 2 ;;
      --body)     body="$2";     shift 2 ;;
      --draft)    draft="true";  shift   ;;
      --base)     base="$2";     shift 2 ;;
      --label)    labels+=("$2"); shift 2 ;;
      --reviewer) reviewers+=("$2"); shift 2 ;;
      *)          extra_args+=("$1"); shift ;;
    esac
  done

  local -a cmd=(gh pr create)
  [[ -n "$title" ]] && cmd+=(--title "$title")
  [[ -n "$body" ]]  && cmd+=(--body "$body")
  [[ -n "$base" ]]  && cmd+=(--base "$base")
  [[ "$draft" == "true" ]] && cmd+=(--draft)

  local label
  for label in "${labels[@]}"; do
    cmd+=(--label "$label")
  done

  local reviewer
  for reviewer in "${reviewers[@]}"; do
    cmd+=(--reviewer "$reviewer")
  done

  cmd+=("${extra_args[@]}")

  local output
  output=$("${cmd[@]}" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  # gh pr create prints the URL on success. Wrap in JSON.
  jq -n --arg url "$output" '{"url": $url}'
}

_github_pr_list() {
  _github_check_auth || return $?

  local -a extra_args=()
  local state="open" limit="30"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state) state="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      *)       extra_args+=("$1"); shift ;;
    esac
  done

  gh pr list --state "$state" --limit "$limit" \
    --json number,title,state,author,url,headRefName,baseRefName,createdAt \
    "${extra_args[@]}"
}

_github_pr_view() {
  _github_check_auth || return $?

  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-view requires a PR number or branch"}' >&2
    return 1
  fi
  shift

  gh pr view "$pr_id" \
    --json number,title,body,state,author,url,labels,reviewRequests,mergeable,headRefName,baseRefName,additions,deletions,changedFiles \
    "$@"
}

_github_pr_diff() {
  _github_check_auth || return $?

  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-diff requires a PR number or branch"}' >&2
    return 1
  fi
  shift

  local diff_output
  diff_output=$(gh pr diff "$pr_id" "$@" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$diff_output" | jq -Rs .)}" >&2
    return 1
  }

  # Wrap raw diff in JSON for consistent output.
  jq -n --arg diff "$diff_output" '{"diff": $diff}'
}

_github_pr_merge() {
  _github_check_auth || return $?

  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-merge requires a PR number"}' >&2
    return 1
  fi
  shift

  local strategy="" delete_branch=""
  local -a extra_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --squash)        strategy="--squash"; shift ;;
      --merge)         strategy="--merge";  shift ;;
      --rebase)        strategy="--rebase"; shift ;;
      --delete-branch) delete_branch="--delete-branch"; shift ;;
      *)               extra_args+=("$1"); shift ;;
    esac
  done

  # Default strategy from config.
  if [[ -z "$strategy" ]]; then
    local cfg_strategy
    cfg_strategy="$(gm_config_get 'pr.merge_strategy' 2>/dev/null || echo "squash")"
    case "$cfg_strategy" in
      squash) strategy="--squash" ;;
      rebase) strategy="--rebase" ;;
      merge)  strategy="--merge"  ;;
      *)      strategy="--squash" ;;
    esac
  fi

  # Default delete-branch from config.
  if [[ -z "$delete_branch" ]]; then
    local cfg_delete
    cfg_delete="$(gm_config_get 'pr.delete_branch_on_merge' 2>/dev/null || echo "true")"
    [[ "$cfg_delete" == "true" ]] && delete_branch="--delete-branch"
  fi

  local -a cmd=(gh pr merge "$pr_id" "$strategy")
  [[ -n "$delete_branch" ]] && cmd+=("$delete_branch")
  cmd+=("${extra_args[@]}")

  local output
  output=$("${cmd[@]}" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg message "$output" '{"merged": true, "message": $message}'
}

_github_pr_close() {
  _github_check_auth || return $?

  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-close requires a PR number"}' >&2
    return 1
  fi
  shift

  local output
  output=$(gh pr close "$pr_id" "$@" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg message "$output" '{"closed": true, "message": $message}'
}

_github_pr_comment() {
  _github_check_auth || return $?

  local pr_id="" body=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body) body="$2"; shift 2 ;;
      *)
        if [[ -z "$pr_id" ]]; then
          pr_id="$1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-comment requires a PR number"}' >&2
    return 1
  fi
  if [[ -z "$body" ]]; then
    echo '{"error":"pr-comment requires --body"}' >&2
    return 1
  fi

  local output
  output=$(gh pr comment "$pr_id" --body "$body" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg url "$output" '{"commented": true, "url": $url}'
}

_github_pr_review() {
  _github_check_auth || return $?

  local pr_id="" body="" action=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body)            body="$2";              shift 2 ;;
      --approve)         action="--approve";     shift   ;;
      --request-changes) action="--request-changes"; shift ;;
      --comment)         action="--comment";     shift   ;;
      *)
        if [[ -z "$pr_id" ]]; then
          pr_id="$1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-review requires a PR number"}' >&2
    return 1
  fi

  local -a cmd=(gh pr review "$pr_id")
  [[ -n "$action" ]] && cmd+=("$action")
  [[ -n "$body" ]]   && cmd+=(--body "$body")

  local output
  output=$("${cmd[@]}" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg message "$output" '{"reviewed": true, "message": $message}'
}

_github_pr_checks() {
  _github_check_auth || return $?

  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-checks requires a PR number"}' >&2
    return 1
  fi
  shift

  # gh pr checks --json is available in recent gh versions.
  # Fall back to tabular output parsed into JSON if --json is not supported.
  local output
  output=$(gh pr checks "$pr_id" --json name,state,conclusion,url 2>&1) && {
    printf '%s' "$output"
    return 0
  }

  # Fallback: parse tabular output.
  local raw
  raw=$(gh pr checks "$pr_id" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$raw" | jq -Rs .)}" >&2
    return 1
  }

  printf '%s' "$raw" | awk -F'\t' '
    BEGIN { printf "[" }
    NR > 1 { printf "," }
    {
      gsub(/"/, "\\\"", $1);
      gsub(/"/, "\\\"", $2);
      gsub(/"/, "\\\"", $3);
      printf "{\"name\":\"%s\",\"state\":\"%s\",\"url\":\"%s\"}", $1, $2, $3
    }
    END { printf "]" }
  '
}

_github_pr_labels() {
  _github_check_auth || return $?

  local pr_id="" action=""
  local -a labels=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --add)    action="add";    shift ;;
      --remove) action="remove"; shift ;;
      --label)  labels+=("$2");  shift 2 ;;
      *)
        if [[ -z "$pr_id" ]]; then
          pr_id="$1"
        else
          labels+=("$1")
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-labels requires a PR number"}' >&2
    return 1
  fi

  local label_str
  label_str="$(IFS=,; printf '%s' "${labels[*]}")"

  local output
  case "$action" in
    add)
      output=$(gh pr edit "$pr_id" --add-label "$label_str" 2>&1) || {
        echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
        return 1
      }
      ;;
    remove)
      output=$(gh pr edit "$pr_id" --remove-label "$label_str" 2>&1) || {
        echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
        return 1
      }
      ;;
    *)
      # No action: list current labels.
      gh pr view "$pr_id" --json labels
      return $?
      ;;
  esac

  jq -n --arg action "$action" --arg labels "$label_str" \
    '{"action": $action, "labels": ($labels | split(","))}'
}

_github_pr_reviewers() {
  _github_check_auth || return $?

  local pr_id=""
  local -a reviewers=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reviewer) reviewers+=("$2"); shift 2 ;;
      *)
        if [[ -z "$pr_id" ]]; then
          pr_id="$1"
        else
          reviewers+=("$1")
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-reviewers requires a PR number"}' >&2
    return 1
  fi

  if [[ ${#reviewers[@]} -eq 0 ]]; then
    # List current reviewers.
    gh pr view "$pr_id" --json reviewRequests
    return $?
  fi

  local reviewer_str
  reviewer_str="$(IFS=,; printf '%s' "${reviewers[*]}")"

  local output
  output=$(gh pr edit "$pr_id" --add-reviewer "$reviewer_str" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg reviewers "$reviewer_str" \
    '{"added_reviewers": ($reviewers | split(","))}'
}

# ---------------------------------------------------------------------------
# CI operations
# ---------------------------------------------------------------------------

_github_ci_status() {
  _github_check_auth || return $?

  local branch=""
  local limit="5"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch) branch="$2"; shift 2 ;;
      --limit)  limit="$2";  shift 2 ;;
      *)        shift ;;
    esac
  done

  # Default to current branch.
  if [[ -z "$branch" ]]; then
    branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"
  fi

  local -a cmd=(gh run list --json "status,conclusion,name,url,event,headBranch,createdAt" --limit "$limit")
  [[ -n "$branch" ]] && cmd+=(--branch "$branch")

  "${cmd[@]}"
}

_github_ci_logs() {
  _github_check_auth || return $?

  local run_id="${1:-}"
  if [[ -z "$run_id" ]]; then
    echo '{"error":"ci-logs requires a run ID"}' >&2
    return 1
  fi
  shift

  local output
  output=$(gh run view "$run_id" --log-failed 2>&1) || {
    # If --log-failed yields nothing, try full log.
    output=$(gh run view "$run_id" --log 2>&1) || {
      echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
      return 1
    }
  }

  jq -n --arg logs "$output" '{"run_id": "'"$run_id"'", "logs": $logs}'
}

_github_ci_retry() {
  _github_check_auth || return $?

  local run_id="${1:-}"
  if [[ -z "$run_id" ]]; then
    echo '{"error":"ci-retry requires a run ID"}' >&2
    return 1
  fi
  shift

  local output
  output=$(gh run rerun "$run_id" --failed 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg message "$output" '{"rerun": true, "message": $message}'
}

# ---------------------------------------------------------------------------
# Repo operations
# ---------------------------------------------------------------------------

_github_repo_info() {
  _github_check_auth || return $?

  gh repo view --json name,owner,defaultBranchRef,description,url,isPrivate "$@"
}

_GM_PROVIDER_GITHUB_LOADED=1
