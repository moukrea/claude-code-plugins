#!/usr/bin/env bash
# provider-generic.sh — Git-only fallback provider.
# Can only perform local operations. Remote/API operations return exit 2.
# Meant to be sourced, not executed directly.

# Guard against double-sourcing.
[[ -n "${_GM_PROVIDER_GENERIC_LOADED:-}" ]] && return 0

# ---------------------------------------------------------------------------
# Unsupported operation helper
# ---------------------------------------------------------------------------

_generic_not_supported() {
  local operation="$1"
  echo "{\"error\":\"'${operation}' is not available without a hosting provider. Configure provider.type in .git-master.yml or use a remote pointing to GitHub, GitLab, Gitea, or Bitbucket.\"}" >&2
  return 2
}

# ---------------------------------------------------------------------------
# PR operations — all unsupported except pr-diff (local)
# ---------------------------------------------------------------------------

_generic_pr_create() {
  _generic_not_supported "pr-create"
}

_generic_pr_list() {
  _generic_not_supported "pr-list"
}

_generic_pr_view() {
  _generic_not_supported "pr-view"
}

_generic_pr_diff() {
  # Local diff: compare current branch against the default base.
  local base="${1:-}"

  if [[ -z "$base" ]]; then
    # Try to determine default base branch.
    base="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')" || true
    [[ -z "$base" ]] && base="main"
  fi

  local current
  current="$(git symbolic-ref --short HEAD 2>/dev/null || echo "HEAD")"

  local diff_output
  diff_output=$(git diff "${base}...${current}" 2>&1) || {
    # Try without the three-dot syntax.
    diff_output=$(git diff "${base}" 2>&1) || {
      echo "{\"error\":\"git diff failed\",\"detail\":$(printf '%s' "$diff_output" | jq -Rs .)}" >&2
      return 1
    }
  }

  jq -n --arg diff "$diff_output" --arg base "$base" --arg head "$current" \
    '{"diff": $diff, "base": $base, "head": $head, "source": "local"}'
}

_generic_pr_merge() {
  _generic_not_supported "pr-merge"
}

_generic_pr_close() {
  _generic_not_supported "pr-close"
}

_generic_pr_comment() {
  _generic_not_supported "pr-comment"
}

_generic_pr_review() {
  _generic_not_supported "pr-review"
}

_generic_pr_checks() {
  _generic_not_supported "pr-checks"
}

_generic_pr_labels() {
  _generic_not_supported "pr-labels"
}

_generic_pr_reviewers() {
  _generic_not_supported "pr-reviewers"
}

# ---------------------------------------------------------------------------
# CI operations — all unsupported
# ---------------------------------------------------------------------------

_generic_ci_status() {
  _generic_not_supported "ci-status"
}

_generic_ci_logs() {
  _generic_not_supported "ci-logs"
}

_generic_ci_retry() {
  _generic_not_supported "ci-retry"
}

# ---------------------------------------------------------------------------
# Repo operations — local info only
# ---------------------------------------------------------------------------

_generic_repo_info() {
  local remote_name
  remote_name="$(gm_config_get 'workflow.default_remote' 2>/dev/null || echo "origin")"
  [[ -z "$remote_name" ]] && remote_name="origin"

  local remote_url
  remote_url="$(git remote get-url "$remote_name" 2>/dev/null || echo "")"

  gm_parse_remote_url "$remote_url" 2>/dev/null || true

  local default_branch
  default_branch="$(git symbolic-ref refs/remotes/${remote_name}/HEAD 2>/dev/null | sed "s|refs/remotes/${remote_name}/||")" || true
  [[ -z "$default_branch" ]] && default_branch="$(git config init.defaultBranch 2>/dev/null || echo "main")"

  local current_branch
  current_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")"

  local toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
  local repo_name
  repo_name="$(basename "$toplevel" 2>/dev/null || echo "unknown")"

  jq -n \
    --arg name "${GM_REMOTE_REPO:-$repo_name}" \
    --arg owner "${GM_REMOTE_OWNER:-}" \
    --arg default_branch "$default_branch" \
    --arg current_branch "$current_branch" \
    --arg remote_url "$remote_url" \
    --arg provider "generic" \
    '{
      name: $name,
      owner: $owner,
      defaultBranch: $default_branch,
      currentBranch: $current_branch,
      remoteUrl: $remote_url,
      provider: $provider,
      note: "Limited to local operations only. Configure a hosting provider for full functionality."
    }'
}

_GM_PROVIDER_GENERIC_LOADED=1
