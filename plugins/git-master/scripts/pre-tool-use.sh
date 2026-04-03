#!/usr/bin/env bash
set -euo pipefail

# Pre-tool-use hook: validate git commits, block pushes to protected branches,
# block force push, validate PR/MR titles.
# Exit 0 = allow, exit 2 = block (stderr becomes Claude feedback).

INPUT=$(cat)

# ---------------------------------------------------------------------------
# Fast path: only care about Bash commands
# ---------------------------------------------------------------------------
tool_name=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[[ -n "$command" ]] || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# ---------------------------------------------------------------------------
# Helper: deny with message
# ---------------------------------------------------------------------------
deny() {
  echo "$1" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Helper: lazy-load config (called only when needed)
# ---------------------------------------------------------------------------
_config_loaded=0
ensure_config() {
  if [[ "$_config_loaded" -eq 0 ]]; then
    # shellcheck source=lib/config.sh
    source "${PLUGIN_ROOT}/scripts/lib/config.sh"
    gm_config_load
    _config_loaded=1
  fi
}

# ---------------------------------------------------------------------------
# Extract commit message from a git commit command
# Returns the message on stdout, or empty string if not found
# ---------------------------------------------------------------------------
extract_commit_message() {
  local cmd="$1"

  # Handle heredoc/cat pattern: git commit -m "$(cat <<'EOF' ... EOF )"
  # Extract content between the heredoc delimiters
  if printf '%s' "$cmd" | grep -qE 'cat\s+<<'; then
    local msg
    msg=$(printf '%s' "$cmd" | sed -n "/cat <<['\"]\\{0,1\\}EOF['\"]\\{0,1\\}/,/^[[:space:]]*EOF/{/cat <</d;/^[[:space:]]*EOF/d;p;}")
    if [[ -n "$msg" ]]; then
      # Trim leading/trailing whitespace
      msg=$(printf '%s' "$msg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      printf '%s' "$msg"
      return
    fi
  fi

  # Handle -m "message" or -m 'message' or -m message
  local msg=""

  # Try double-quoted: -m "..."
  if printf '%s' "$cmd" | grep -qE -- '-m\s+"'; then
    msg=$(printf '%s' "$cmd" | sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p')
  # Try single-quoted: -m '...'
  elif printf '%s' "$cmd" | grep -qE -- "-m\s+'"; then
    msg=$(printf '%s' "$cmd" | sed -n "s/.*-m[[:space:]]*'\\([^']*\\)'.*/\\1/p")
  # Try unquoted: -m word (next arg)
  elif printf '%s' "$cmd" | grep -qE -- '-m\s+\S'; then
    msg=$(printf '%s' "$cmd" | sed -n 's/.*-m[[:space:]]*\([^[:space:]"'"'"'][^[:space:]]*\).*/\1/p')
  fi

  printf '%s' "$msg"
}

# ---------------------------------------------------------------------------
# Validate a commit message against configured convention
# ---------------------------------------------------------------------------
validate_commit_message() {
  local msg="$1"

  ensure_config

  # Check skip patterns first
  local skip_patterns
  skip_patterns=$(gm_config_get_array 'commit.skip_patterns' 2>/dev/null || true)
  if [[ -n "$skip_patterns" ]]; then
    while IFS= read -r pattern; do
      [[ -z "$pattern" ]] && continue
      if printf '%s' "$msg" | grep -qE "$pattern"; then
        return 0
      fi
    done <<< "$skip_patterns"
  fi

  local convention
  convention=$(gm_config_get 'commit.convention' || echo "conventional")

  # Extract subject line (first line of message)
  local subject
  subject=$(printf '%s' "$msg" | head -n1)

  local max_length
  max_length=$(gm_config_get 'commit.subject.max_length' || echo "72")
  if [[ -n "$max_length" && "$max_length" != "null" ]]; then
    local len=${#subject}
    if (( len > max_length )); then
      deny "[git-master] Commit subject too long (${len}/${max_length} chars): ${subject}"
    fi
  fi

  case "$convention" in
    conventional|angular)
      # Pattern: type(scope)!: description
      if ! printf '%s' "$subject" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+'; then
        deny "[git-master] Invalid ${convention} commit format.
Expected: <type>(<scope>): <description>
Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
Got: ${subject}"
      fi

      # Extract type and check against allowed list
      local ctype
      ctype=$(printf '%s' "$subject" | sed -n 's/^\([a-z]*\).*/\1/p')
      local allowed_types
      allowed_types=$(gm_config_get_array 'commit.types' 2>/dev/null || true)
      if [[ -n "$allowed_types" && -n "$ctype" ]]; then
        if ! printf '%s\n' "$allowed_types" | grep -qx "$ctype"; then
          deny "[git-master] Commit type '${ctype}' is not in the allowed list.
Allowed: $(printf '%s' "$allowed_types" | tr '\n' ', ' | sed 's/,$//')"
        fi
      fi

      # Check scope_required
      local scope_required
      scope_required=$(gm_config_get 'commit.scope_required' || echo "false")
      if [[ "$scope_required" == "true" ]]; then
        if ! printf '%s' "$subject" | grep -qE '^[a-z]+\(.+\)'; then
          deny "[git-master] Scope is required. Expected: <type>(<scope>): <description>"
        fi
      fi

      # Extract description (after "type(scope): " or "type: ")
      local description
      description=$(printf '%s' "$subject" | sed -n 's/^[a-z]*\(([^)]*)\)\{0,1\}!*:[[:space:]]*//p')

      # Check case
      local case_rule
      case_rule=$(gm_config_get 'commit.subject.case' || echo "lower")
      if [[ "$case_rule" == "lower" && -n "$description" ]]; then
        local first_char
        first_char=$(printf '%s' "$description" | cut -c1)
        if printf '%s' "$first_char" | grep -q '[A-Z]'; then
          deny "[git-master] Commit description must start with a lowercase letter. Got: '${description}'"
        fi
      fi

      # Check trailing period
      local no_trailing_period
      no_trailing_period=$(gm_config_get 'commit.subject.no_trailing_period' || echo "true")
      if [[ "$no_trailing_period" == "true" ]]; then
        if printf '%s' "$subject" | grep -qE '\.$'; then
          deny "[git-master] Commit subject must not end with a period."
        fi
      fi
      ;;

    gitmoji)
      # Must start with :emoji: or a unicode emoji
      if ! printf '%s' "$subject" | grep -qE '^(:[a-z_]+:|[\x{1F300}-\x{1F9FF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}])'; then
        # Fallback: check for common unicode emoji byte patterns
        if ! printf '%s' "$subject" | grep -qP '^\p{Emoji_Presentation}'; then
          deny "[git-master] Gitmoji commit must start with an emoji (e.g., :sparkles: or a unicode emoji).
Got: ${subject}"
        fi
      fi
      ;;

    custom)
      local custom_pattern
      custom_pattern=$(gm_config_get 'commit.custom_pattern' || echo "")
      local custom_desc
      custom_desc=$(gm_config_get 'commit.custom_description' || echo "")
      if [[ -n "$custom_pattern" && "$custom_pattern" != "null" ]]; then
        if ! printf '%s' "$subject" | grep -qE "$custom_pattern"; then
          local hint=""
          [[ -n "$custom_desc" && "$custom_desc" != "null" ]] && hint=" ($custom_desc)"
          deny "[git-master] Commit does not match custom pattern${hint}.
Pattern: ${custom_pattern}
Got: ${subject}"
        fi
      fi
      ;;

    freeform)
      # Only length check (already done above)
      ;;

    *)
      # Unknown convention — skip validation
      ;;
  esac

  return 0
}

# ---------------------------------------------------------------------------
# Validate a PR/MR title
# ---------------------------------------------------------------------------
validate_pr_title() {
  local title="$1"

  ensure_config

  local pr_convention
  pr_convention=$(gm_config_get 'pr.title.convention' || echo "inherit")

  # "inherit" means use the commit convention
  [[ "$pr_convention" == "inherit" ]] && pr_convention=$(gm_config_get 'commit.convention' || echo "conventional")

  local pr_max_length
  pr_max_length=$(gm_config_get 'pr.title.max_length' || echo "72")
  if [[ -n "$pr_max_length" && "$pr_max_length" != "null" ]]; then
    local len=${#title}
    if (( len > pr_max_length )); then
      deny "[git-master] PR/MR title too long (${len}/${pr_max_length} chars): ${title}"
    fi
  fi

  case "$pr_convention" in
    conventional|angular)
      if ! printf '%s' "$title" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+'; then
        deny "[git-master] PR/MR title must follow ${pr_convention} format.
Expected: <type>(<scope>): <description>
Got: ${title}"
      fi
      ;;
    custom)
      local custom_pattern
      custom_pattern=$(gm_config_get 'pr.title.custom_pattern' || echo "")
      if [[ -n "$custom_pattern" && "$custom_pattern" != "null" ]]; then
        if ! printf '%s' "$title" | grep -qE "$custom_pattern"; then
          deny "[git-master] PR/MR title does not match required pattern.
Pattern: ${custom_pattern}
Got: ${title}"
        fi
      fi
      ;;
    freeform|""|null)
      # No format enforcement
      ;;
  esac

  return 0
}

# ---------------------------------------------------------------------------
# Extract --title from a gh pr create / glab mr create command
# ---------------------------------------------------------------------------
extract_pr_title() {
  local cmd="$1"

  local title=""
  # Try --title "..." or --title '...'
  if printf '%s' "$cmd" | grep -qE -- '--title\s+"'; then
    title=$(printf '%s' "$cmd" | sed -n 's/.*--title[[:space:]]*"\([^"]*\)".*/\1/p')
  elif printf '%s' "$cmd" | grep -qE -- "--title\s+'"; then
    title=$(printf '%s' "$cmd" | sed -n "s/.*--title[[:space:]]*'\\([^']*\\)'.*/\\1/p")
  elif printf '%s' "$cmd" | grep -qE -- '--title\s+\S'; then
    title=$(printf '%s' "$cmd" | sed -n 's/.*--title[[:space:]]*\([^[:space:]"'"'"'][^[:space:]]*\).*/\1/p')
  fi

  printf '%s' "$title"
}

# ===========================================================================
# Main dispatch
# ===========================================================================

# --- git commit ---
if printf '%s' "$command" | grep -qE '(^|[;&|]\s*)git\s+commit\b'; then
  # Check for -m flag — if absent, it is an interactive commit; allow it
  if ! printf '%s' "$command" | grep -qE -- '-m\s'; then
    exit 0
  fi

  msg=$(extract_commit_message "$command")
  if [[ -z "$msg" ]]; then
    exit 0
  fi

  validate_commit_message "$msg"
  exit 0
fi

# --- git push ---
if printf '%s' "$command" | grep -qE '(^|[;&|]\s*)git\s+push\b'; then
  # Check for force push (but allow --force-with-lease)
  if printf '%s' "$command" | grep -qE -- '(--force|-f)(\s|$)' && \
     ! printf '%s' "$command" | grep -qE -- '--force-with-lease'; then
    deny "[git-master] Force push is blocked. Use --force-with-lease for safer force pushes."
  fi

  # Check protected branches
  current_branch=$(git branch --show-current 2>/dev/null || echo "")
  if [[ -n "$current_branch" ]]; then
    ensure_config
    protected=$(gm_config_get_array 'branch.protected' 2>/dev/null || true)
    if [[ -n "$protected" ]]; then
      while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue
        if [[ "$current_branch" == "$branch" ]]; then
          deny "[git-master] Push to protected branch '${branch}' is blocked. Create a PR/MR instead."
        fi
      done <<< "$protected"
    fi
  fi

  exit 0
fi

# --- gh pr create / glab mr create ---
if printf '%s' "$command" | grep -qE '(^|[;&|]\s*)(gh\s+pr\s+create|glab\s+mr\s+create)\b'; then
  title=$(extract_pr_title "$command")
  if [[ -n "$title" ]]; then
    validate_pr_title "$title"
  fi
  exit 0
fi

# --- Everything else: allow ---
exit 0
