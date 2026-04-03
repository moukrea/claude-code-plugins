#!/usr/bin/env bash
# provider-gitlab.sh — GitLab provider implementation.
# Primary: glab CLI. Fallback: GitLab API v4 via curl.
# Meant to be sourced, not executed directly.

# Guard against double-sourcing.
[[ -n "${_GM_PROVIDER_GITLAB_LOADED:-}" ]] && return 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Check that glab is available and authenticated.
_gitlab_check_auth() {
  if ! command -v glab &>/dev/null; then
    echo '{"error":"glab CLI not found"}' >&2
    return 1
  fi
  if ! glab auth status &>/dev/null 2>&1; then
    echo '{"error":"glab CLI not authenticated. Run: glab auth login"}' >&2
    return 3
  fi
  return 0
}

# Determine the GitLab host (for API fallback).
_gitlab_host() {
  local host
  host="$(gm_config_get 'provider.host' 2>/dev/null || echo "")"
  if [[ -n "$host" && "$host" != *"="* ]]; then
    printf '%s' "$host"
    return
  fi
  # Parse from remote URL.
  local remote_name
  remote_name="$(gm_config_get 'workflow.default_remote' 2>/dev/null || echo "origin")"
  [[ -z "$remote_name" ]] && remote_name="origin"
  local url
  url="$(git remote get-url "$remote_name" 2>/dev/null || true)"
  _gm_extract_host "$url"
}

# URL-encoded project path for API calls: group/subgroup/repo -> group%2Fsubgroup%2Frepo
_gitlab_project_path() {
  gm_parse_remote_url
  local full_path="${GM_REMOTE_OWNER}/${GM_REMOTE_REPO}"
  printf '%s' "$full_path" | jq -sRr @uri
}

# Get an auth token for curl fallback.
_gitlab_token() {
  local token_env
  token_env="$(gm_config_get 'provider.token_env' 2>/dev/null || echo "")"
  if [[ -n "$token_env" ]]; then
    printf '%s' "${!token_env:-}"
    return
  fi
  printf '%s' "${GITLAB_TOKEN:-${GITLAB_PRIVATE_TOKEN:-}}"
}

# Authenticated curl wrapper for the GitLab REST API.
_gitlab_curl() {
  local method="$1" endpoint="$2"
  shift 2
  local token
  token="$(_gitlab_token)"
  if [[ -z "$token" ]]; then
    echo '{"error":"no GitLab token available for API fallback"}' >&2
    return 3
  fi
  local host
  host="$(_gitlab_host)"
  [[ -z "$host" ]] && host="gitlab.com"
  local url="https://${host}/api/v4${endpoint}"
  curl -sf -X "$method" \
    -H "PRIVATE-TOKEN: $token" \
    -H "Content-Type: application/json" \
    "$@" "$url"
}

# ---------------------------------------------------------------------------
# PR (Merge Request) operations
# ---------------------------------------------------------------------------

_gitlab_pr_create() {
  _gitlab_check_auth || {
    # Fallback to API.
    _gitlab_api_mr_create "$@"
    return $?
  }

  local title="" body="" draft="" target=""
  local -a labels=() reviewers=() extra_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)    title="$2";    shift 2 ;;
      --body)     body="$2";     shift 2 ;;
      --draft)    draft="true";  shift   ;;
      --base)     target="$2";   shift 2 ;;
      --label)    labels+=("$2"); shift 2 ;;
      --reviewer) reviewers+=("$2"); shift 2 ;;
      *)          extra_args+=("$1"); shift ;;
    esac
  done

  local -a cmd=(glab mr create --fill)
  [[ -n "$title" ]] && cmd+=(--title "$title")
  [[ -n "$body" ]]  && cmd+=(--description "$body")
  [[ -n "$target" ]] && cmd+=(--target-branch "$target")
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

  # glab mr create prints the MR URL on success.
  jq -n --arg url "$output" '{"url": $url}'
}

_gitlab_api_mr_create() {
  local title="" body="" target="" draft="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --body)  body="$2";  shift 2 ;;
      --base)  target="$2"; shift 2 ;;
      --draft) draft="true"; shift ;;
      *)       shift ;;
    esac
  done

  local source_branch
  source_branch="$(git symbolic-ref --short HEAD 2>/dev/null)"

  local project_path
  project_path="$(_gitlab_project_path)"

  local payload
  payload=$(jq -n \
    --arg title "$title" \
    --arg desc "$body" \
    --arg source "$source_branch" \
    --arg target "$target" \
    --argjson draft "$draft" \
    '{title: $title, description: $desc, source_branch: $source, target_branch: $target, draft: $draft}')

  _gitlab_curl POST "/projects/${project_path}/merge_requests" -d "$payload"
}

_gitlab_pr_list() {
  _gitlab_check_auth || {
    local project_path
    project_path="$(_gitlab_project_path)"
    _gitlab_curl GET "/projects/${project_path}/merge_requests?state=opened&per_page=30"
    return $?
  }

  local state="opened" limit=""
  local -a extra_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state) state="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      *)       extra_args+=("$1"); shift ;;
    esac
  done

  # Map generic state names to glab equivalents.
  case "$state" in
    open) state="opened" ;;
    closed|merged) ;; # These are valid for glab.
  esac

  local -a glab_args=(glab mr list --state "$state")
  [[ -n "$limit" ]] && glab_args+=(--per-page "$limit")
  glab_args+=("${extra_args[@]}")

  local output
  output=$("${glab_args[@]}" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  # glab mr list outputs a table. Convert to JSON.
  _gitlab_table_to_json "$output"
}

_gitlab_pr_view() {
  _gitlab_check_auth || {
    local mr_id="${1:-}"
    local project_path
    project_path="$(_gitlab_project_path)"
    _gitlab_curl GET "/projects/${project_path}/merge_requests/${mr_id}"
    return $?
  }

  local mr_id="${1:-}"
  if [[ -z "$mr_id" ]]; then
    echo '{"error":"pr-view requires an MR number"}' >&2
    return 1
  fi
  shift

  local output
  output=$(glab mr view "$mr_id" --output json 2>&1) && {
    printf '%s' "$output"
    return 0
  }

  # Fallback: parse non-JSON output.
  output=$(glab mr view "$mr_id" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg raw "$output" '{"raw": $raw}'
}

_gitlab_pr_diff() {
  _gitlab_check_auth || {
    local mr_id="${1:-}"
    local project_path
    project_path="$(_gitlab_project_path)"
    local diff_json
    diff_json=$(_gitlab_curl GET "/projects/${project_path}/merge_requests/${mr_id}/changes")
    printf '%s' "$diff_json"
    return $?
  }

  local mr_id="${1:-}"
  if [[ -z "$mr_id" ]]; then
    echo '{"error":"pr-diff requires an MR number"}' >&2
    return 1
  fi
  shift

  local output
  output=$(glab mr diff "$mr_id" "$@" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg diff "$output" '{"diff": $diff}'
}

_gitlab_pr_merge() {
  _gitlab_check_auth || {
    local mr_id="${1:-}"
    local project_path
    project_path="$(_gitlab_project_path)"
    _gitlab_curl PUT "/projects/${project_path}/merge_requests/${mr_id}/merge"
    return $?
  }

  local mr_id="${1:-}"
  if [[ -z "$mr_id" ]]; then
    echo '{"error":"pr-merge requires an MR number"}' >&2
    return 1
  fi
  shift

  local -a extra_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --squash|--merge|--rebase|--delete-branch)
        extra_args+=("$1"); shift ;;
      *) shift ;;
    esac
  done

  local output
  output=$(glab mr merge "$mr_id" "${extra_args[@]}" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg message "$output" '{"merged": true, "message": $message}'
}

_gitlab_pr_close() {
  _gitlab_check_auth || {
    local mr_id="${1:-}"
    local project_path
    project_path="$(_gitlab_project_path)"
    _gitlab_curl PUT "/projects/${project_path}/merge_requests/${mr_id}" \
      -d '{"state_event":"close"}'
    return $?
  }

  local mr_id="${1:-}"
  if [[ -z "$mr_id" ]]; then
    echo '{"error":"pr-close requires an MR number"}' >&2
    return 1
  fi
  shift

  local output
  output=$(glab mr close "$mr_id" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg message "$output" '{"closed": true, "message": $message}'
}

_gitlab_pr_comment() {
  _gitlab_check_auth || {
    local mr_id="" body=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --body) body="$2"; shift 2 ;;
        *)      [[ -z "$mr_id" ]] && mr_id="$1"; shift ;;
      esac
    done
    local project_path
    project_path="$(_gitlab_project_path)"
    _gitlab_curl POST "/projects/${project_path}/merge_requests/${mr_id}/notes" \
      -d "$(jq -n --arg body "$body" '{body: $body}')"
    return $?
  }

  local mr_id="" body=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body) body="$2"; shift 2 ;;
      *)      [[ -z "$mr_id" ]] && mr_id="$1"; shift ;;
    esac
  done

  if [[ -z "$mr_id" ]]; then
    echo '{"error":"pr-comment requires an MR number"}' >&2
    return 1
  fi

  local output
  output=$(glab mr note "$mr_id" --message "$body" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg message "$output" '{"commented": true, "message": $message}'
}

_gitlab_pr_review() {
  _gitlab_check_auth || return $?

  local mr_id="" body="" action=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body)            body="$2"; shift 2 ;;
      --approve)         action="approve"; shift ;;
      --request-changes) action="unapprove"; shift ;;
      --comment)         action="comment"; shift ;;
      *)                 [[ -z "$mr_id" ]] && mr_id="$1"; shift ;;
    esac
  done

  if [[ -z "$mr_id" ]]; then
    echo '{"error":"pr-review requires an MR number"}' >&2
    return 1
  fi

  local output
  case "$action" in
    approve)
      output=$(glab mr approve "$mr_id" 2>&1) || {
        echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
        return 1
      }
      ;;
    unapprove)
      output=$(glab mr unapprove "$mr_id" 2>&1) || {
        echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
        return 1
      }
      # Also leave a comment with the body if provided.
      if [[ -n "$body" ]]; then
        glab mr note "$mr_id" --message "$body" &>/dev/null || true
      fi
      ;;
    comment|*)
      if [[ -n "$body" ]]; then
        output=$(glab mr note "$mr_id" --message "$body" 2>&1) || {
          echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
          return 1
        }
      fi
      ;;
  esac

  jq -n --arg action "${action:-comment}" --arg message "${output:-ok}" \
    '{"reviewed": true, "action": $action, "message": $message}'
}

_gitlab_pr_checks() {
  _gitlab_check_auth || {
    local mr_id="${1:-}"
    local project_path
    project_path="$(_gitlab_project_path)"
    # Use pipelines associated with the MR.
    _gitlab_curl GET "/projects/${project_path}/merge_requests/${mr_id}/pipelines"
    return $?
  }

  # glab ci status shows the pipeline status for the current branch.
  local output
  output=$(glab ci status 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg raw "$output" '{"raw": $raw}'
}

_gitlab_pr_labels() {
  _gitlab_check_auth || return $?

  local mr_id="" action=""
  local -a labels=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --add)    action="add"; shift ;;
      --remove) action="remove"; shift ;;
      --label)  labels+=("$2"); shift 2 ;;
      *)
        if [[ -z "$mr_id" ]]; then mr_id="$1"; else labels+=("$1"); fi
        shift
        ;;
    esac
  done

  if [[ -z "$mr_id" ]]; then
    echo '{"error":"pr-labels requires an MR number"}' >&2
    return 1
  fi

  local label_str
  label_str="$(IFS=,; printf '%s' "${labels[*]}")"

  local output
  case "$action" in
    add)
      output=$(glab mr update "$mr_id" --label "$label_str" 2>&1) || {
        echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
        return 1
      }
      ;;
    remove)
      output=$(glab mr update "$mr_id" --unlabel "$label_str" 2>&1) || {
        echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
        return 1
      }
      ;;
    *)
      glab mr view "$mr_id" --output json 2>/dev/null | jq '{labels: .labels}' 2>/dev/null || {
        echo '{"labels": []}'
      }
      return 0
      ;;
  esac

  jq -n --arg action "$action" --arg labels "$label_str" \
    '{"action": $action, "labels": ($labels | split(","))}'
}

_gitlab_pr_reviewers() {
  _gitlab_check_auth || return $?

  local mr_id=""
  local -a reviewers=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reviewer) reviewers+=("$2"); shift 2 ;;
      *)
        if [[ -z "$mr_id" ]]; then mr_id="$1"; else reviewers+=("$1"); fi
        shift
        ;;
    esac
  done

  if [[ -z "$mr_id" ]]; then
    echo '{"error":"pr-reviewers requires an MR number"}' >&2
    return 1
  fi

  if [[ ${#reviewers[@]} -eq 0 ]]; then
    glab mr view "$mr_id" --output json 2>/dev/null | jq '{reviewers: .reviewers}' 2>/dev/null || {
      echo '{"reviewers": []}'
    }
    return 0
  fi

  local reviewer_str
  reviewer_str="$(IFS=,; printf '%s' "${reviewers[*]}")"

  local output
  output=$(glab mr update "$mr_id" --reviewer "$reviewer_str" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg reviewers "$reviewer_str" \
    '{"added_reviewers": ($reviewers | split(","))}'
}

# ---------------------------------------------------------------------------
# CI operations
# ---------------------------------------------------------------------------

_gitlab_ci_status() {
  _gitlab_check_auth || {
    local project_path
    project_path="$(_gitlab_project_path)"
    _gitlab_curl GET "/projects/${project_path}/pipelines?per_page=5&order_by=id&sort=desc"
    return $?
  }

  local output
  output=$(glab ci status --output json 2>&1) && {
    printf '%s' "$output"
    return 0
  }

  # Fallback: plain text.
  output=$(glab ci status 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg raw "$output" '{"raw": $raw}'
}

_gitlab_ci_logs() {
  _gitlab_check_auth || return $?

  local job_id="${1:-}"

  local output
  if [[ -n "$job_id" ]]; then
    output=$(glab ci trace "$job_id" 2>&1) || {
      echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
      return 1
    }
  else
    output=$(glab ci trace 2>&1) || {
      echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
      return 1
    }
  fi

  jq -n --arg logs "$output" '{"logs": $logs}'
}

_gitlab_ci_retry() {
  _gitlab_check_auth || {
    local pipeline_id="${1:-}"
    local project_path
    project_path="$(_gitlab_project_path)"
    _gitlab_curl POST "/projects/${project_path}/pipelines/${pipeline_id}/retry"
    return $?
  }

  local pipeline_id="${1:-}"
  if [[ -z "$pipeline_id" ]]; then
    echo '{"error":"ci-retry requires a pipeline or job ID"}' >&2
    return 1
  fi

  local output
  output=$(glab ci retry "$pipeline_id" 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg message "$output" '{"rerun": true, "message": $message}'
}

# ---------------------------------------------------------------------------
# Repo operations
# ---------------------------------------------------------------------------

_gitlab_repo_info() {
  _gitlab_check_auth || {
    local project_path
    project_path="$(_gitlab_project_path)"
    _gitlab_curl GET "/projects/${project_path}"
    return $?
  }

  local output
  output=$(glab repo view --output json 2>&1) && {
    printf '%s' "$output"
    return 0
  }

  # Fallback: parse text output.
  output=$(glab repo view 2>&1) || {
    echo "{\"error\":$(printf '%s' "$output" | jq -Rs .)}" >&2
    return 1
  }

  jq -n --arg raw "$output" '{"raw": $raw}'
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Best-effort conversion of glab tabular output to JSON array.
_gitlab_table_to_json() {
  local raw="$1"
  # Try to parse as tab-separated with header.
  printf '%s' "$raw" | awk '
    BEGIN { FS="\t"; ORS="" }
    NR == 1 {
      n = split($0, headers)
      next
    }
    NR == 2 { printf "[" }
    NR > 2 { printf "," }
    {
      printf "{"
      for (i = 1; i <= NF && i <= n; i++) {
        gsub(/"/, "\\\"", $i)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
        gsub(/"/, "\\\"", headers[i])
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", headers[i])
        if (i > 1) printf ","
        printf "\"%s\":\"%s\"", tolower(headers[i]), $i
      }
      printf "}"
    }
    END { printf "]" }
  '
}

_GM_PROVIDER_GITLAB_LOADED=1
