#!/usr/bin/env bash
# provider-gitea.sh — Gitea/Forgejo/Codeberg provider implementation.
# Primary: tea CLI. Fallback: Gitea API v1 via curl.
# Meant to be sourced, not executed directly.

# Guard against double-sourcing.
[[ -n "${_GM_PROVIDER_GITEA_LOADED:-}" ]] && return 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_gitea_check_cli() {
  if ! command -v tea &>/dev/null; then
    return 1
  fi
  return 0
}

# Determine the Gitea instance host.
_gitea_host() {
  local host
  host="$(gm_config_get 'provider.host' 2>/dev/null || echo "")"
  if [[ -n "$host" && "$host" != *"="* ]]; then
    printf '%s' "$host"
    return
  fi
  local remote_name
  remote_name="$(gm_config_get 'workflow.default_remote' 2>/dev/null || echo "origin")"
  [[ -z "$remote_name" ]] && remote_name="origin"
  local url
  url="$(git remote get-url "$remote_name" 2>/dev/null || true)"
  _gm_extract_host "$url"
}

# Get an auth token for curl fallback.
_gitea_token() {
  local token_env
  token_env="$(gm_config_get 'provider.token_env' 2>/dev/null || echo "")"
  if [[ -n "$token_env" ]]; then
    printf '%s' "${!token_env:-}"
    return
  fi
  printf '%s' "${GITEA_TOKEN:-${TEA_TOKEN:-}}"
}

# Authenticated curl wrapper for the Gitea REST API v1.
_gitea_curl() {
  local method="$1" endpoint="$2"
  shift 2
  local token
  token="$(_gitea_token)"
  if [[ -z "$token" ]]; then
    echo '{"error":"no Gitea token available for API fallback"}' >&2
    return 3
  fi
  local host
  host="$(_gitea_host)"
  if [[ -z "$host" ]]; then
    echo '{"error":"cannot determine Gitea host"}' >&2
    return 1
  fi
  local url="https://${host}/api/v1${endpoint}"
  curl -sf -X "$method" \
    -H "Authorization: token $token" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "$@" "$url"
}

# Get owner/repo for API paths.
_gitea_owner_repo() {
  gm_parse_remote_url
  printf '%s/%s' "$GM_REMOTE_OWNER" "$GM_REMOTE_REPO"
}

# ---------------------------------------------------------------------------
# PR (Pull Request) operations
# ---------------------------------------------------------------------------

_gitea_pr_create() {
  local title="" body="" draft="" base=""
  local -a labels=() extra_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)    title="$2";    shift 2 ;;
      --body)     body="$2";     shift 2 ;;
      --draft)    draft="true";  shift   ;;
      --base)     base="$2";     shift 2 ;;
      --label)    labels+=("$2"); shift 2 ;;
      --reviewer) shift 2 ;; # Reviewers not directly supported in tea.
      *)          extra_args+=("$1"); shift ;;
    esac
  done

  local source_branch
  source_branch="$(git symbolic-ref --short HEAD 2>/dev/null)"

  if _gitea_check_cli; then
    local -a cmd=(tea pr create --title "$title" --description "$body")
    [[ -n "$base" ]] && cmd+=(--base "$base")
    [[ "$draft" == "true" ]] && cmd+=(--draft)
    cmd+=("${extra_args[@]}")

    local output
    output=$("${cmd[@]}" 2>&1) || {
      echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
      return 1
    }
    jq -n --arg url "$output" '{"url": $url}'
    return 0
  fi

  # API fallback.
  local owner_repo
  owner_repo="$(_gitea_owner_repo)"

  [[ -z "$base" ]] && base="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")"

  local payload
  payload=$(jq -n \
    --arg title "$title" \
    --arg body "$body" \
    --arg head "$source_branch" \
    --arg base "$base" \
    '{title: $title, body: $body, head: $head, base: $base}')

  _gitea_curl POST "/repos/${owner_repo}/pulls" -d "$payload"
}

_gitea_pr_list() {
  local state="open" limit="30"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state) state="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      *)       shift ;;
    esac
  done

  if _gitea_check_cli; then
    local output
    output=$(tea pr list --state "$state" --limit "$limit" --output simple 2>&1) || {
      echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
      return 1
    }
    jq -n --arg raw "$output" '{"raw": $raw}'
    return 0
  fi

  local owner_repo
  owner_repo="$(_gitea_owner_repo)"
  _gitea_curl GET "/repos/${owner_repo}/pulls?state=${state}&limit=${limit}"
}

_gitea_pr_view() {
  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-view requires a PR number"}' >&2
    return 1
  fi

  if _gitea_check_cli; then
    local output
    output=$(tea pr view "$pr_id" --output simple 2>&1) || {
      echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
      return 1
    }
    jq -n --arg raw "$output" '{"raw": $raw}'
    return 0
  fi

  local owner_repo
  owner_repo="$(_gitea_owner_repo)"
  _gitea_curl GET "/repos/${owner_repo}/pulls/${pr_id}"
}

_gitea_pr_diff() {
  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-diff requires a PR number"}' >&2
    return 1
  fi

  # tea does not have a diff command; use API.
  local owner_repo
  owner_repo="$(_gitea_owner_repo)"
  local token
  token="$(_gitea_token)"
  local host
  host="$(_gitea_host)"

  if [[ -n "$token" && -n "$host" ]]; then
    local diff_output
    diff_output=$(curl -sf \
      -H "Authorization: token $token" \
      -H "Accept: text/plain" \
      "https://${host}/api/v1/repos/${owner_repo}/pulls/${pr_id}.diff" 2>&1) || {
      echo "{\"error\":\"failed to fetch diff\"}" >&2
      return 1
    }
    jq -n --arg diff "$diff_output" '{"diff": $diff}'
    return 0
  fi

  echo '{"error":"pr-diff requires a Gitea token for API access"}' >&2
  return 3
}

_gitea_pr_merge() {
  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-merge requires a PR number"}' >&2
    return 1
  fi
  shift

  local strategy="squash"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --squash) strategy="squash"; shift ;;
      --merge)  strategy="merge";  shift ;;
      --rebase) strategy="rebase"; shift ;;
      *)        shift ;;
    esac
  done

  if _gitea_check_cli; then
    local output
    output=$(tea pr merge "$pr_id" --style "$strategy" 2>&1) || {
      echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
      return 1
    }
    jq -n --arg message "$output" '{"merged": true, "message": $message}'
    return 0
  fi

  local owner_repo
  owner_repo="$(_gitea_owner_repo)"
  local payload
  payload=$(jq -n --arg method "$strategy" '{"Do": $method}')
  _gitea_curl POST "/repos/${owner_repo}/pulls/${pr_id}/merge" -d "$payload"
}

_gitea_pr_close() {
  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-close requires a PR number"}' >&2
    return 1
  fi

  if _gitea_check_cli; then
    local output
    output=$(tea pr close "$pr_id" 2>&1) || {
      echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
      return 1
    }
    jq -n --arg message "$output" '{"closed": true, "message": $message}'
    return 0
  fi

  local owner_repo
  owner_repo="$(_gitea_owner_repo)"
  _gitea_curl PATCH "/repos/${owner_repo}/pulls/${pr_id}" -d '{"state":"closed"}'
}

_gitea_pr_comment() {
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

  local owner_repo
  owner_repo="$(_gitea_owner_repo)"
  local payload
  payload=$(jq -n --arg body "$body" '{body: $body}')
  _gitea_curl POST "/repos/${owner_repo}/issues/${pr_id}/comments" -d "$payload"
}

_gitea_pr_review() {
  # Gitea API supports reviews but tea CLI does not directly.
  local pr_id="" body="" action=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body)            body="$2"; shift 2 ;;
      --approve)         action="APPROVED"; shift ;;
      --request-changes) action="REQUEST_CHANGES"; shift ;;
      --comment)         action="COMMENT"; shift ;;
      *)                 [[ -z "$pr_id" ]] && pr_id="$1"; shift ;;
    esac
  done

  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-review requires a PR number"}' >&2
    return 1
  fi

  [[ -z "$action" ]] && action="COMMENT"

  local owner_repo
  owner_repo="$(_gitea_owner_repo)"
  local payload
  payload=$(jq -n --arg body "${body:-}" --arg event "$action" \
    '{body: $body, event: $event}')
  _gitea_curl POST "/repos/${owner_repo}/pulls/${pr_id}/reviews" -d "$payload"
}

_gitea_pr_checks() {
  # Gitea does not have built-in CI. Check commit status API.
  local pr_id="${1:-}"
  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-checks requires a PR number"}' >&2
    return 1
  fi

  local owner_repo
  owner_repo="$(_gitea_owner_repo)"

  # Get the PR to find the head SHA.
  local pr_data
  pr_data=$(_gitea_curl GET "/repos/${owner_repo}/pulls/${pr_id}" 2>/dev/null) || {
    echo '{"error":"failed to fetch PR details"}' >&2
    return 1
  }

  local sha
  sha=$(printf '%s' "$pr_data" | jq -r '.head.sha // empty')
  if [[ -z "$sha" ]]; then
    echo '{"checks": [], "note": "no commit status available"}'
    return 0
  fi

  _gitea_curl GET "/repos/${owner_repo}/statuses/${sha}"
}

_gitea_pr_labels() {
  local pr_id="" action=""
  local -a labels=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --add)    action="add"; shift ;;
      --remove) action="remove"; shift ;;
      --label)  labels+=("$2"); shift 2 ;;
      *)
        if [[ -z "$pr_id" ]]; then pr_id="$1"; else labels+=("$1"); fi
        shift
        ;;
    esac
  done

  if [[ -z "$pr_id" ]]; then
    echo '{"error":"pr-labels requires a PR number"}' >&2
    return 1
  fi

  local owner_repo
  owner_repo="$(_gitea_owner_repo)"

  case "$action" in
    add)
      # Gitea uses label IDs, not names. Look up IDs first.
      local label_ids="[]"
      local label
      for label in "${labels[@]}"; do
        local lid
        lid=$(_gitea_curl GET "/repos/${owner_repo}/labels?name=${label}" 2>/dev/null \
          | jq -r '.[0].id // empty')
        if [[ -n "$lid" ]]; then
          label_ids=$(printf '%s' "$label_ids" | jq --argjson id "$lid" '. + [$id]')
        fi
      done
      _gitea_curl POST "/repos/${owner_repo}/issues/${pr_id}/labels" \
        -d "{\"labels\": $label_ids}"
      ;;
    remove)
      local label
      for label in "${labels[@]}"; do
        local lid
        lid=$(_gitea_curl GET "/repos/${owner_repo}/labels?name=${label}" 2>/dev/null \
          | jq -r '.[0].id // empty')
        if [[ -n "$lid" ]]; then
          _gitea_curl DELETE "/repos/${owner_repo}/issues/${pr_id}/labels/${lid}" || true
        fi
      done
      jq -n '{"removed": true}'
      ;;
    *)
      _gitea_curl GET "/repos/${owner_repo}/issues/${pr_id}/labels"
      ;;
  esac
}

_gitea_pr_reviewers() {
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

  local owner_repo
  owner_repo="$(_gitea_owner_repo)"

  if [[ ${#reviewers[@]} -eq 0 ]]; then
    _gitea_curl GET "/repos/${owner_repo}/pulls/${pr_id}/reviews"
    return $?
  fi

  local payload
  payload=$(jq -n --argjson reviewers "$(printf '%s\n' "${reviewers[@]}" | jq -R . | jq -s .)" \
    '{reviewers: $reviewers}')
  _gitea_curl POST "/repos/${owner_repo}/pulls/${pr_id}/requested_reviewers" -d "$payload"
}

# ---------------------------------------------------------------------------
# CI operations
# ---------------------------------------------------------------------------

_gitea_ci_status() {
  # Gitea does not have native CI; report commit statuses on the current branch.
  local branch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch) branch="$2"; shift 2 ;;
      *)        shift ;;
    esac
  done

  [[ -z "$branch" ]] && branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"

  local owner_repo
  owner_repo="$(_gitea_owner_repo)"

  # Get the latest commit on the branch.
  local sha
  sha=$(git rev-parse "origin/${branch}" 2>/dev/null || git rev-parse HEAD 2>/dev/null || echo "")
  if [[ -z "$sha" ]]; then
    echo '{"error":"cannot determine HEAD commit"}' >&2
    return 1
  fi

  _gitea_curl GET "/repos/${owner_repo}/statuses/${sha}"
}

_gitea_ci_logs() {
  echo '{"error":"ci-logs not supported for Gitea (no built-in CI)"}' >&2
  return 2
}

_gitea_ci_retry() {
  echo '{"error":"ci-retry not supported for Gitea (no built-in CI)"}' >&2
  return 2
}

# ---------------------------------------------------------------------------
# Repo operations
# ---------------------------------------------------------------------------

_gitea_repo_info() {
  local owner_repo
  owner_repo="$(_gitea_owner_repo)"
  _gitea_curl GET "/repos/${owner_repo}"
}

_GM_PROVIDER_GITEA_LOADED=1
