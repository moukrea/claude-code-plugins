#!/usr/bin/env bash
# provider-bitbucket.sh — Bitbucket Cloud provider implementation.
# REST API only (no standard CLI tool).
# Uses: https://api.bitbucket.org/2.0/
# Meant to be sourced, not executed directly.

# Guard against double-sourcing.
[[ -n "${_GM_PROVIDER_BITBUCKET_LOADED:-}" ]] && return 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Get an auth token (app password or OAuth token).
_bitbucket_token() {
  local token_env
  token_env="$(gm_config_get 'provider.token_env' 2>/dev/null || echo "")"
  if [[ -n "$token_env" ]]; then
    printf '%s' "${!token_env:-}"
    return
  fi
  printf '%s' "${BITBUCKET_TOKEN:-${BITBUCKET_APP_PASSWORD:-}}"
}

# Get the Bitbucket username for basic auth.
_bitbucket_username() {
  printf '%s' "${BITBUCKET_USERNAME:-}"
}

# Authenticated curl wrapper for the Bitbucket REST API 2.0.
# Supports both token auth (Bearer) and basic auth (user:app_password).
_bitbucket_curl() {
  local method="$1" endpoint="$2"
  shift 2

  local token username
  token="$(_bitbucket_token)"
  username="$(_bitbucket_username)"

  local -a auth_args=()
  if [[ -n "$username" && -n "$token" ]]; then
    # Basic auth with app password.
    auth_args=(-u "${username}:${token}")
  elif [[ -n "$token" ]]; then
    # Bearer token (OAuth).
    auth_args=(-H "Authorization: Bearer $token")
  else
    echo '{"error":"no Bitbucket credentials available. Set BITBUCKET_USERNAME and BITBUCKET_TOKEN (app password) or BITBUCKET_TOKEN (OAuth)"}' >&2
    return 3
  fi

  local url="https://api.bitbucket.org/2.0${endpoint}"
  curl -sf -X "$method" \
    "${auth_args[@]}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "$@" "$url"
}

# Get workspace/repo slug for API paths.
_bitbucket_workspace_repo() {
  gm_parse_remote_url
  printf '%s/%s' "$GM_REMOTE_OWNER" "$GM_REMOTE_REPO"
}

# ---------------------------------------------------------------------------
# PR (Pull Request) operations
# ---------------------------------------------------------------------------

_bitbucket_pr_create() {
  # shellcheck disable=SC2034  # draft is parsed for interface consistency but Bitbucket has no draft PRs
  local title="" body="" draft="" base=""
  local -a reviewers=()

  # shellcheck disable=SC2034  # draft parsed for interface consistency; Bitbucket has no draft PRs
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)    title="$2";    shift 2 ;;
      --body)     body="$2";     shift 2 ;;
      --draft)    draft="true";  shift   ;;
      --base)     base="$2";     shift 2 ;;
      --label)    shift 2 ;; # Bitbucket does not have labels on PRs.
      --reviewer) reviewers+=("$2"); shift 2 ;;
      *)          shift ;;
    esac
  done

  local source_branch
  source_branch="$(git symbolic-ref --short HEAD 2>/dev/null)"

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"

  # Build reviewers array.
  local reviewers_json="[]"
  local r
  for r in "${reviewers[@]}"; do
    reviewers_json=$(printf '%s' "$reviewers_json" | jq --arg u "$r" '. + [{"username": $u}]')
  done

  # Default base branch.
  if [[ -z "$base" ]]; then
    base="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")"
  fi

  local payload
  payload=$(jq -n \
    --arg title "$title" \
    --arg desc "$body" \
    --arg source "$source_branch" \
    --arg dest "$base" \
    --argjson reviewers "$reviewers_json" \
    --argjson close_source "$(val=$(gm_config_get 'pr.delete_branch_on_merge' 2>/dev/null || echo "true"); [[ "$val" == "true" ]] && echo "true" || echo "false")" \
    '{
      title: $title,
      description: $desc,
      source: {branch: {name: $source}},
      destination: {branch: {name: $dest}},
      reviewers: $reviewers,
      close_source_branch: $close_source
    }')

  _bitbucket_curl POST "/repositories/${ws_repo}/pullrequests" -d "$payload"
}

_bitbucket_pr_list() {
  local state="OPEN" limit="30"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state)
        case "$2" in
          open)   state="OPEN" ;;
          closed) state="MERGED,DECLINED" ;;
          merged) state="MERGED" ;;
          *)      state="$2" ;;
        esac
        shift 2
        ;;
      --limit) limit="$2"; shift 2 ;;
      *)       shift ;;
    esac
  done

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"
  _bitbucket_curl GET "/repositories/${ws_repo}/pullrequests?state=${state}&pagelen=${limit}"
}

_bitbucket_pr_view() {
  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-view requires a PR number"}' >&2
    return 1
  fi

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"
  _bitbucket_curl GET "/repositories/${ws_repo}/pullrequests/${pr_id}"
}

_bitbucket_pr_diff() {
  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-diff requires a PR number"}' >&2
    return 1
  fi

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"

  local token username
  token="$(_bitbucket_token)"
  username="$(_bitbucket_username)"

  local -a auth_args=()
  if [[ -n "$username" && -n "$token" ]]; then
    auth_args=(-u "${username}:${token}")
  elif [[ -n "$token" ]]; then
    auth_args=(-H "Authorization: Bearer $token")
  else
    echo '{"error":"no Bitbucket credentials for diff"}' >&2
    return 3
  fi

  local diff_output
  diff_output=$(curl -sf \
    "${auth_args[@]}" \
    -H "Accept: text/plain" \
    "https://api.bitbucket.org/2.0/repositories/${ws_repo}/pullrequests/${pr_id}/diff" 2>&1) || {
    echo '{"error":"failed to fetch diff"}' >&2
    return 1
  }

  jq -n --arg diff "$diff_output" '{"diff": $diff}'
}

_bitbucket_pr_merge() {
  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-merge requires a PR number"}' >&2
    return 1
  fi
  shift

  local strategy="squash"
  local close_source="true"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --squash)        strategy="squash"; shift ;;
      --merge)         strategy="merge_commit"; shift ;;
      --rebase)        strategy="fast_forward"; shift ;; # Closest Bitbucket equivalent.
      --delete-branch) close_source="true"; shift ;;
      *)               shift ;;
    esac
  done

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"

  local payload
  payload=$(jq -n \
    --arg strategy "$strategy" \
    --argjson close "$close_source" \
    '{merge_strategy: $strategy, close_source_branch: $close}')

  _bitbucket_curl POST "/repositories/${ws_repo}/pullrequests/${pr_id}/merge" -d "$payload"
}

_bitbucket_pr_close() {
  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-close requires a PR number"}' >&2
    return 1
  fi

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"

  # Bitbucket uses "decline" to close a PR without merging.
  _bitbucket_curl POST "/repositories/${ws_repo}/pullrequests/${pr_id}/decline"
}

_bitbucket_pr_comment() {
  local pr_id="" body=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body) body="$2"; shift 2 ;;
      *)      [[ -z "$pr_id" ]] && pr_id="$1"; shift ;;
    esac
  done

  if [[ -z "$pr_id" || -z "$body" ]]; then
    echo '{"error":"pr-comment requires a PR number and --body"}' >&2
    return 1
  fi

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"

  local payload
  payload=$(jq -n --arg body "$body" '{content: {raw: $body}}')
  _bitbucket_curl POST "/repositories/${ws_repo}/pullrequests/${pr_id}/comments" -d "$payload"
}

_bitbucket_pr_review() {
  local pr_id="" body="" action=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body)            body="$2"; shift 2 ;;
      --approve)         action="approve"; shift ;;
      --request-changes) action="request-changes"; shift ;;
      --comment)         action="comment"; shift ;;
      *)                 [[ -z "$pr_id" ]] && pr_id="$1"; shift ;;
    esac
  done

  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-review requires a PR number"}' >&2
    return 1
  fi

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"

  case "$action" in
    approve)
      _bitbucket_curl POST "/repositories/${ws_repo}/pullrequests/${pr_id}/approve"
      ;;
    request-changes)
      _bitbucket_curl DELETE "/repositories/${ws_repo}/pullrequests/${pr_id}/approve" || true
      # Bitbucket has no native "request changes". Leave a comment instead.
      if [[ -n "$body" ]]; then
        local payload
        payload=$(jq -n --arg body "$body" '{content: {raw: $body}}')
        _bitbucket_curl POST "/repositories/${ws_repo}/pullrequests/${pr_id}/comments" -d "$payload"
      fi
      jq -n '{"reviewed": true, "action": "request-changes", "note": "Bitbucket does not natively support request-changes; approval removed and comment posted"}'
      ;;
    comment|*)
      if [[ -n "$body" ]]; then
        local payload
        payload=$(jq -n --arg body "$body" '{content: {raw: $body}}')
        _bitbucket_curl POST "/repositories/${ws_repo}/pullrequests/${pr_id}/comments" -d "$payload"
      fi
      ;;
  esac
}

_bitbucket_pr_checks() {
  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-checks requires a PR number"}' >&2
    return 1
  fi

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"
  _bitbucket_curl GET "/repositories/${ws_repo}/pullrequests/${pr_id}/statuses"
}

_bitbucket_pr_labels() {
  # Bitbucket Cloud does not support labels on pull requests.
  echo '{"error":"labels are not supported on Bitbucket Cloud pull requests"}' >&2
  return 2
}

_bitbucket_pr_reviewers() {
  local pr_id=""
  local -a reviewers=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reviewer) reviewers+=("$2"); shift 2 ;;
      *)
        if [[ -z "$pr_id" ]]; then pr_id="$1"; else reviewers+=("$1"); fi
        shift
        ;;
    esac
  done

  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-reviewers requires a PR number"}' >&2
    return 1
  fi

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"

  if [[ ${#reviewers[@]} -eq 0 ]]; then
    # List current reviewers.
    _bitbucket_curl GET "/repositories/${ws_repo}/pullrequests/${pr_id}" \
      | jq '{reviewers: [.reviewers[]? | {username: .username, display_name: .display_name}]}'
    return $?
  fi

  # Update reviewers by patching the PR.
  local reviewers_json="[]"
  local r
  for r in "${reviewers[@]}"; do
    reviewers_json=$(printf '%s' "$reviewers_json" | jq --arg u "$r" '. + [{"username": $u}]')
  done

  local payload
  payload=$(jq -n --argjson reviewers "$reviewers_json" '{reviewers: $reviewers}')
  _bitbucket_curl PUT "/repositories/${ws_repo}/pullrequests/${pr_id}" -d "$payload"
}

# ---------------------------------------------------------------------------
# CI operations
# ---------------------------------------------------------------------------

_bitbucket_ci_status() {
  local branch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch) branch="$2"; shift 2 ;;
      *)        shift ;;
    esac
  done

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"

  # Bitbucket Pipelines: list pipeline results.
  local endpoint="/repositories/${ws_repo}/pipelines/?sort=-created_on&pagelen=5"
  if [[ -n "$branch" ]]; then
    endpoint="/repositories/${ws_repo}/pipelines/?sort=-created_on&pagelen=5&target.ref_name=${branch}"
  fi

  _bitbucket_curl GET "$endpoint"
}

_bitbucket_ci_logs() {
  local pipeline_id="${1:-}"
  if [[ -z "$pipeline_id" ]]; then
    echo '{"error":"ci-logs requires a pipeline UUID"}' >&2
    return 1
  fi

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"

  # List steps in the pipeline, then fetch logs for each.
  local steps
  steps=$(_bitbucket_curl GET "/repositories/${ws_repo}/pipelines/${pipeline_id}/steps/") || {
    echo '{"error":"failed to fetch pipeline steps"}' >&2
    return 1
  }

  local step_uuids
  step_uuids=$(printf '%s' "$steps" | jq -r '.values[]?.uuid // empty')
  if [[ -z "$step_uuids" ]]; then
    printf '%s' "$steps"
    return 0
  fi

  local result="[]"
  local uuid
  while IFS= read -r uuid; do
    [[ -z "$uuid" ]] && continue
    local log
    log=$(_bitbucket_curl GET "/repositories/${ws_repo}/pipelines/${pipeline_id}/steps/${uuid}/log" 2>/dev/null || echo "")
    result=$(printf '%s' "$result" | jq --arg uuid "$uuid" --arg log "$log" \
      '. + [{step: $uuid, log: $log}]')
  done <<< "$step_uuids"

  printf '%s' "$result"
}

_bitbucket_ci_retry() {
  # Bitbucket Pipelines: trigger a new run on the same commit/branch.
  local pipeline_id="${1:-}"

  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"

  if [[ -n "$pipeline_id" ]]; then
    # Get the pipeline details to find the target branch.
    local pipeline
    pipeline=$(_bitbucket_curl GET "/repositories/${ws_repo}/pipelines/${pipeline_id}") || {
      echo '{"error":"failed to fetch pipeline details"}' >&2
      return 1
    }
    local branch
    branch=$(printf '%s' "$pipeline" | jq -r '.target.ref_name // empty')
    if [[ -z "$branch" ]]; then
      echo '{"error":"could not determine branch from pipeline"}' >&2
      return 1
    fi
    local payload
    payload=$(jq -n --arg branch "$branch" \
      '{target: {type: "pipeline_ref_target", ref_type: "branch", ref_name: $branch}}')
    _bitbucket_curl POST "/repositories/${ws_repo}/pipelines/" -d "$payload"
  else
    echo '{"error":"ci-retry requires a pipeline UUID"}' >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Repo operations
# ---------------------------------------------------------------------------

_bitbucket_repo_info() {
  local ws_repo
  ws_repo="$(_bitbucket_workspace_repo)"
  _bitbucket_curl GET "/repositories/${ws_repo}"
}

_GM_PROVIDER_BITBUCKET_LOADED=1
