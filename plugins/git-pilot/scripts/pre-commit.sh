#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=./git-utils.sh
source "$SCRIPT_DIR/git-utils.sh"
# shellcheck source=./state.sh
source "$SCRIPT_DIR/state.sh"

# --- Output helpers ---

output_allow() {
  cat <<'ALLOW_JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
ALLOW_JSON
  exit 0
}

output_allow_with_message() {
  local msg="$1"
  jq -n --arg msg "$msg" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow"
    },
    systemMessage: $msg
  }'
  exit 0
}

output_allow_with_updated_input() {
  local new_command="$1"
  jq -n --arg cmd "$new_command" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      updatedInput: {
        command: $cmd
      }
    }
  }'
  exit 0
}

output_allow_with_message_and_updated_input() {
  local msg="$1"
  local new_command="$2"
  jq -n --arg msg "$msg" --arg cmd "$new_command" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      updatedInput: {
        command: $cmd
      }
    },
    systemMessage: $msg
  }'
  exit 0
}

output_block() {
  local error_msg="$1"
  echo "$error_msg" >&2
  exit 2
}

# --- Command detection ---

# Returns 0 if the command contains a git commit as an actual command (not a substring).
# For chained commands (&&, ||, ;), checks each segment.
# Skips pipe targets and quoted strings.
is_git_commit_command() {
  local cmd="$1"

  # Strip leading whitespace
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"

  # Skip commands where git commit is quoted (e.g., echo "git commit")
  if [[ "$cmd" =~ ^(echo|printf)[[:space:]] ]]; then
    return 1
  fi

  # Split on &&, ||, ; (chain operators) and check each segment.
  # Pipe targets (|) are skipped — the command after | is not a standalone command.
  # Use newline as IFS-safe delimiter by replacing chain operators.
  local segments
  segments=$(echo "$cmd" | sed -E 's/[[:space:]]*(&&|\|\||;)[[:space:]]*/\n/g')

  while IFS= read -r segment; do
    # Strip leading whitespace from segment
    segment="${segment#"${segment%%[![:space:]]*}"}"

    # Skip pipe chains — only consider the part before the first pipe
    segment=$(echo "$segment" | sed -E 's/[[:space:]]*\|[[:space:]].*$//')

    # Skip echo/printf commands
    if [[ "$segment" =~ ^(echo|printf)[[:space:]] ]]; then
      continue
    fi

    if [[ "$segment" =~ ^git[[:space:]]+commit([[:space:]]|$) ]]; then
      return 0
    fi
  done <<< "$segments"

  return 1
}

# Returns 0 if the command is a branch creation command. Sets BRANCH_NAME.
is_branch_creation_command() {
  local cmd="$1"
  BRANCH_NAME=""

  # git checkout -b <name>
  if [[ "$cmd" =~ git[[:space:]]+checkout[[:space:]]+(-b)[[:space:]]+([^[:space:]]+) ]]; then
    BRANCH_NAME="${BASH_REMATCH[2]}"
    return 0
  fi

  # git switch -c <name>
  if [[ "$cmd" =~ git[[:space:]]+switch[[:space:]]+(-c)[[:space:]]+([^[:space:]]+) ]]; then
    BRANCH_NAME="${BASH_REMATCH[2]}"
    return 0
  fi

  # git branch <name> (but not git branch -d, -D, -m, -M, -a, -l, --list, etc.)
  if [[ "$cmd" =~ git[[:space:]]+branch[[:space:]]+([^-][^[:space:]]*) ]]; then
    BRANCH_NAME="${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

# Returns 0 if the command is a branch switch command (not branch creation).
# Sets SWITCH_TARGET to the target branch name.
is_branch_switch_command() {
  local cmd="$1"
  SWITCH_TARGET=""

  # git checkout <branch> (not -b/-B for new branch creation)
  if [[ "$cmd" =~ git[[:space:]]+checkout[[:space:]]+([^-][^[:space:]]+) ]] && \
     ! [[ "$cmd" =~ git[[:space:]]+checkout[[:space:]]+-[bB] ]]; then
    SWITCH_TARGET="${BASH_REMATCH[1]}"
    return 0
  fi

  # git switch <branch> (not -c/-C for new branch creation)
  if [[ "$cmd" =~ git[[:space:]]+switch[[:space:]]+([^-][^[:space:]]+) ]] && \
     ! [[ "$cmd" =~ git[[:space:]]+switch[[:space:]]+-[cC] ]]; then
    SWITCH_TARGET="${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

# --- Commit message parsing ---

# Extracts the commit message from a git commit command.
# Sets COMMIT_MSG and HAS_MESSAGE.
parse_commit_message() {
  local cmd="$1"
  COMMIT_MSG=""
  HAS_MESSAGE=false

  # Check for heredoc form: -m "$(cat <<'EOF' ... EOF )"
  if [[ "$cmd" =~ \<\< ]]; then
    # Extract the delimiter name first, then use it in a range match
    local delim
    delim=$(echo "$cmd" | sed -n "s/.*<<[[:space:]]*'*\([A-Za-z_][A-Za-z_]*\)'*.*/\1/p" | head -n 1)
    if [[ -n "$delim" ]]; then
      local heredoc_content
      heredoc_content=$(echo "$cmd" | sed -n "/<<.*${delim}/,/^${delim}$/{
        /<<.*${delim}/d
        /^${delim}$/d
        p
      }" 2>/dev/null || true)
      if [[ -n "$heredoc_content" ]]; then
        COMMIT_MSG="$heredoc_content"
        HAS_MESSAGE=true
        return 0
      fi
    fi
  fi

  # Check for multiple -m flags: collect all and join with blank lines
  local messages=()
  local temp_cmd="$cmd"

  # Match --message="..." or --message='...'
  while [[ "$temp_cmd" =~ --message=[\"\'](([^\"\']*))[\"\'] ]]; do
    messages+=("${BASH_REMATCH[1]}")
    temp_cmd="${temp_cmd/${BASH_REMATCH[0]}/}"
  done

  # Match -m "..." or -m '...' or -am "..." or -am '...'
  # We need a more careful approach to handle multiple -m flags
  temp_cmd="$cmd"
  if [[ ${#messages[@]} -eq 0 ]]; then
    # Use a loop with a regex to find all -m arguments
    while true; do
      # Match -m or -am followed by quoted string
      if [[ "$temp_cmd" =~ (-[a-z]*m)[[:space:]]+\"([^\"]*)\"|(-[a-z]*m)[[:space:]]+\'([^\']*)\' ]]; then
        local msg="${BASH_REMATCH[2]}${BASH_REMATCH[4]}"
        messages+=("$msg")
        temp_cmd="${temp_cmd/${BASH_REMATCH[0]}/}"
      else
        break
      fi
    done
  fi

  if [[ ${#messages[@]} -gt 0 ]]; then
    # Join messages with blank lines (conventional multi-paragraph commit)
    local joined=""
    for i in "${!messages[@]}"; do
      if [[ $i -gt 0 ]]; then
        joined+=$'\n\n'
      fi
      joined+="${messages[$i]}"
    done
    COMMIT_MSG="$joined"
    HAS_MESSAGE=true
    return 0
  fi

  # No message flag found — editor mode, skip validation
  return 0
}

# --- Pattern-to-regex conversion for commit messages ---

build_commit_regex() {
  local config="$1"
  local pattern types_json scope_required types_str

  pattern=$(echo "$config" | jq -r '.commit.pattern // "{{type}}({{scope}}): {{description}}"')
  types_json=$(echo "$config" | jq -r '.commit.types // ["feat","fix","docs","style","refactor","perf","test","build","ci","chore","revert"]')
  scope_required=$(echo "$config" | jq -r '.commit.scopeRequired // false')

  # Build the types alternation
  types_str=$(echo "$types_json" | jq -r 'join("|")')

  # Start building the regex from the pattern template.
  # The default pattern is: {{type}}({{scope}}): {{description}}
  # where the parens around {{scope}} are literal characters in the template.

  local regex="$pattern"

  # Replace {{type}} with type alternation
  regex="${regex//\{\{type\}\}/($types_str)}"

  # Replace {{description}} with (.+)
  regex="${regex//\{\{description\}\}/(.+)}"

  # Handle scope based on scopeRequired.
  # The pattern contains literal "({{scope}})" which means the parens are part of the
  # commit message format (e.g., "feat(auth): description").
  if [[ "$scope_required" == "true" ]]; then
    # Scope is mandatory — replace ({{scope}}) with escaped literal parens and capture group
    regex="${regex/\(\{\{scope\}\}\)/\\([a-zA-Z][a-zA-Z0-9_-]*\\)}"
  else
    # Scope is optional — make the entire "(scope)" part optional including the literal parens
    regex="${regex/\(\{\{scope\}\}\)/(\\([a-zA-Z][a-zA-Z0-9_-]*\\))?}"
  fi

  # Handle bare {{scope}} without surrounding parens (if any remain)
  regex="${regex//\{\{scope\}\}/([a-zA-Z][a-zA-Z0-9_-]*)}"

  # Replace {{ticket}} if present
  regex="${regex//\{\{ticket\}\}/([A-Z]+-[0-9]+)}"

  # Add optional ! for breaking changes after type/scope, before the colon
  regex="${regex/: /!?: }"

  # Anchor the regex
  echo "^${regex}$"
}

# --- Signature stripping ---

strip_signatures() {
  local config="$1"
  local message="$2"
  local stripped="$message"
  local was_modified=false

  local strip_coauthor strip_ai strip_signoff
  strip_coauthor=$(echo "$config" | jq -r '.commit.signature.stripCoAuthoredBy // true')
  strip_ai=$(echo "$config" | jq -r '.commit.signature.stripAiAttribution // true')
  strip_signoff=$(echo "$config" | jq -r '.commit.signature.stripSignedOffBy // false')

  if [[ "$strip_coauthor" == "true" ]]; then
    local new_stripped
    new_stripped=$(echo "$stripped" | grep -vi '^[[:space:]]*Co-authored-by:' || true)
    if [[ "$new_stripped" != "$stripped" ]]; then
      stripped="$new_stripped"
      was_modified=true
    fi
  fi

  if [[ "$strip_ai" == "true" ]]; then
    local new_stripped
    new_stripped=$(echo "$stripped" | grep -viE '^[[:space:]]*(Generated with|Generated by|Created with|Created by)[[:space:]].*(Claude|GPT|Copilot|ChatGPT|AI|Gemini|Cursor|Cody)' || true)
    if [[ "$new_stripped" != "$stripped" ]]; then
      stripped="$new_stripped"
      was_modified=true
    fi
  fi

  if [[ "$strip_signoff" == "true" ]]; then
    local new_stripped
    new_stripped=$(echo "$stripped" | grep -vi '^[[:space:]]*Signed-off-by:' || true)
    if [[ "$new_stripped" != "$stripped" ]]; then
      stripped="$new_stripped"
      was_modified=true
    fi
  fi

  # Remove trailing blank lines
  stripped=$(echo "$stripped" | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')

  if [[ "$was_modified" == true ]]; then
    STRIPPED_MSG="$stripped"
    return 0
  else
    return 1
  fi
}

# Reconstructs the git commit command with a new message.
# Strips all existing -m/--message arguments and re-adds the cleaned message.
rebuild_commit_command() {
  local cmd="$1"
  local new_message="$2"

  # Remove all existing -m/--message arguments from the command.
  # Handle: -m "...", -m '...', -am "...", -am '...', --message="...", --message='...'
  local new_cmd="$cmd"
  # Remove --message="..." or --message='...'
  new_cmd=$(echo "$new_cmd" | sed -E "s/--message=[\"'][^\"']*[\"']//g")
  # Remove -m "..." or -m '...' or -am "..." etc. (flag + space + quoted string)
  new_cmd=$(echo "$new_cmd" | sed -E "s/-[a-z]*m[[:space:]]+[\"'][^\"']*[\"']//g")
  # Trim extra spaces
  new_cmd=$(echo "$new_cmd" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')

  # Re-add -m flags from the cleaned message.
  # Split on blank lines to produce separate -m arguments (multi-paragraph convention).
  local paragraph=""
  local in_paragraph=false
  while IFS= read -r line; do
    if [[ -z "$line" ]] && [[ "$in_paragraph" == true ]]; then
      # End of a paragraph — flush it
      new_cmd+=" -m \"$paragraph\""
      paragraph=""
      in_paragraph=false
    else
      if [[ "$in_paragraph" == true ]]; then
        paragraph+=$'\n'"$line"
      else
        paragraph="$line"
        in_paragraph=true
      fi
    fi
  done <<< "$new_message"

  # Flush the last paragraph
  if [[ "$in_paragraph" == true ]] && [[ -n "$paragraph" ]]; then
    new_cmd+=" -m \"$paragraph\""
  fi

  echo "$new_cmd"
}

# --- Branch name validation ---

validate_branch_name() {
  local config="$1"
  local branch_name="$2"
  local warning_msg=""

  local branch_pattern branch_types_json branch_desc_case branch_max_length branch_types_str
  branch_pattern=$(echo "$config" | jq -r '.branch.pattern // "{{type}}/{{description}}"')
  branch_types_json=$(echo "$config" | jq -r '.branch.types // ["feat","fix","refactor","docs","test","chore","style","perf","build","ci"]')
  branch_desc_case=$(echo "$config" | jq -r '.branch.descriptionCase // "kebab"')
  branch_max_length=$(echo "$config" | jq -r '.branch.maxLength // 72')

  branch_types_str=$(echo "$branch_types_json" | jq -r 'join("|")')
  local branch_types_display
  branch_types_display=$(echo "$branch_types_json" | jq -r 'join(", ")')

  # Build the regex for branch name
  local regex="$branch_pattern"

  # Replace {{type}}
  regex="${regex//\{\{type\}\}/($branch_types_str)}"

  # Replace {{description}} based on case
  case "$branch_desc_case" in
    kebab)
      regex="${regex//\{\{description\}\}/([a-z][a-z0-9]*(-[a-z0-9]+)*)}"
      ;;
    snake)
      regex="${regex//\{\{description\}\}/([a-z][a-z0-9]*(_[a-z0-9]+)*)}"
      ;;
    camel)
      regex="${regex//\{\{description\}\}/([a-z][a-zA-Z0-9]*)}"
      ;;
    *)
      regex="${regex//\{\{description\}\}/(.+)}"
      ;;
  esac

  # Replace {{scope}} if present
  regex="${regex//\{\{scope\}\}/([a-zA-Z][a-zA-Z0-9_-]*)}"

  # Replace {{ticket}} if present
  regex="${regex//\{\{ticket\}\}/([A-Z]+-[0-9]+)}"

  # Escape forward slashes for the regex
  regex="${regex//\//\\/}"

  # Anchor
  regex="^${regex}$"

  # Check length
  local name_length=${#branch_name}
  if (( name_length > branch_max_length )); then
    warning_msg="[git-pilot] Branch name '${branch_name}' exceeds maximum length of ${branch_max_length} (got ${name_length})."
  fi

  # Check pattern match
  if ! echo "$branch_name" | grep -qE "$regex" 2>/dev/null; then
    local example_desc
    case "$branch_desc_case" in
      kebab) example_desc="add-auth" ;;
      snake) example_desc="add_auth" ;;
      camel) example_desc="addAuth" ;;
      *) example_desc="add-auth" ;;
    esac
    # Build example from the pattern
    local example="${branch_pattern}"
    # Pick the first type from the list
    local first_type
    first_type=$(echo "$branch_types_json" | jq -r '.[0]')
    example="${example//\{\{type\}\}/$first_type}"
    example="${example//\{\{description\}\}/$example_desc}"

    warning_msg="[git-pilot] Branch name '${branch_name}' does not match the expected pattern.
  Expected: ${branch_pattern} (${branch_desc_case}-case)
  Types: ${branch_types_display}
  Example: ${example}"
  fi

  if [[ -n "$warning_msg" ]]; then
    BRANCH_WARNING="$warning_msg"
    return 1
  fi
  return 0
}

# --- Main ---

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Only process Bash tool invocations
if [[ "$TOOL_NAME" != "Bash" ]]; then
  output_allow
fi

# If no command, allow
if [[ -z "$COMMAND" ]]; then
  output_allow
fi

# Load config
CONFIG=$(load_config "$CWD")

# --- Branch switch detection with auto-stash ---
SWITCH_TARGET=""
if is_branch_switch_command "$COMMAND"; then
  auto_stash_cfg=$(get_config "$CONFIG" '.branch.autoStashOnSwitch' 'true')
  if [[ "$auto_stash_cfg" == "true" ]] && has_uncommitted_changes; then
    current_br=$(get_current_branch)
    if auto_stash "$current_br" "$SESSION_ID"; then
      output_allow_with_message "[git-pilot] Stashed uncommitted changes on '${current_br}' before switching to '${SWITCH_TARGET}'."
    fi
  fi
fi

# --- Branch creation detection ---
BRANCH_NAME=""
BRANCH_WARNING=""
if is_branch_creation_command "$COMMAND"; then
  # Sanitize the branch name first
  local_sanitized=$(sanitize_branch_name "$BRANCH_NAME")

  if ! validate_branch_name "$CONFIG" "$local_sanitized"; then
    # Warn but do not block
    if ! is_git_commit_command "$COMMAND"; then
      output_allow_with_message "$BRANCH_WARNING"
    fi
    # If it's also a commit command somehow, we'll handle that below and include the warning
  fi
fi

# --- Git commit detection ---
if ! is_git_commit_command "$COMMAND"; then
  # Not a commit command. If we had a branch warning, it was already handled above.
  output_allow
fi

# Reset state file change counter on commit detection
if [[ -n "$SESSION_ID" ]]; then
  STATE_FILE=$(get_state_file "$SESSION_ID")
  if [[ -f "$STATE_FILE" ]]; then
    update_state "$STATE_FILE" '.changeCount = 0 | .modifiedFiles = [] | .lastCommitAt = (now | todate)'
  fi
fi

# Parse the commit message
COMMIT_MSG=""
HAS_MESSAGE=false
parse_commit_message "$COMMAND"

# If no -m flag found, skip validation (editor mode / --amend without -m)
if [[ "$HAS_MESSAGE" != true ]]; then
  # Still check branch protection
  protect_mode=$(get_config "$CONFIG" '.git.protectDefaultBranch' 'warn')
  protect_mode=$(normalize_protect_default_branch "$protect_mode")
  if is_on_default_branch "$CONFIG" 2>/dev/null; then
    default_br=$(get_default_branch "$CONFIG")
    case "$protect_mode" in
      warn)
        output_allow_with_message "[git-pilot] Warning: You are committing directly to '${default_br}'. Consider creating a feature branch first."
        ;;
      block)
        output_block "[git-pilot] Commits to '${default_br}' are blocked by policy (git.protectDefaultBranch: block). Create a feature branch first using /branch."
        ;;
      off)
        ;;
    esac
  fi
  output_allow
fi

# Extract the subject line (first line of the message)
SUBJECT=$(echo "$COMMIT_MSG" | head -n 1)

# WIP bypass: if message starts with wipPrefix, skip all validation
WIP_PREFIX=$(echo "$CONFIG" | jq -r '.autoCommit.wipPrefix // "wip: "')
if [[ "$SUBJECT" == "$WIP_PREFIX"* ]]; then
  # Check branch protection even for WIP commits
  protect_mode=$(get_config "$CONFIG" '.git.protectDefaultBranch' 'warn')
  protect_mode=$(normalize_protect_default_branch "$protect_mode")
  if is_on_default_branch "$CONFIG" 2>/dev/null; then
    default_br=$(get_default_branch "$CONFIG")
    case "$protect_mode" in
      warn)
        output_allow_with_message "[git-pilot] Warning: You are committing directly to '${default_br}'. Consider creating a feature branch first."
        ;;
      block)
        output_block "[git-pilot] Commits to '${default_br}' are blocked by policy (git.protectDefaultBranch: block). Create a feature branch first using /branch."
        ;;
      off)
        ;;
    esac
  fi
  output_allow
fi

# --- Commit message validation ---

COMMIT_PATTERN=$(echo "$CONFIG" | jq -r '.commit.pattern // "{{type}}({{scope}}): {{description}}"')
COMMIT_TYPES_JSON=$(echo "$CONFIG" | jq -r '.commit.types // ["feat","fix","docs","style","refactor","perf","test","build","ci","chore","revert"]')
SCOPE_REQUIRED=$(echo "$CONFIG" | jq -r '.commit.scopeRequired // false')
MAX_SUBJECT_LENGTH=$(echo "$CONFIG" | jq -r '.commit.maxSubjectLength // 72')

# Build the regex
COMMIT_REGEX=$(build_commit_regex "$CONFIG")

# Check if the subject matches the pattern
if ! echo "$SUBJECT" | grep -qE "$COMMIT_REGEX" 2>/dev/null; then
  output_block "[git-pilot] Commit message format error:
  Expected: ${COMMIT_PATTERN}
  Got: ${SUBJECT}
  Issue: message does not match pattern '${COMMIT_PATTERN}'
  Example: feat(auth): add SSO login support"
fi

# Extract type for further validation
COMMIT_TYPES_STR=$(echo "$COMMIT_TYPES_JSON" | jq -r 'join("|")')
if [[ "$SUBJECT" =~ ^($COMMIT_TYPES_STR) ]]; then
  : # Type matched, continue validation
fi

# Check subject length
SUBJECT_LENGTH=${#SUBJECT}
if (( SUBJECT_LENGTH > MAX_SUBJECT_LENGTH )); then
  output_block "[git-pilot] Commit message format error:
  Expected: ${COMMIT_PATTERN}
  Got: ${SUBJECT}
  Issue: subject length ${SUBJECT_LENGTH} exceeds maximum of ${MAX_SUBJECT_LENGTH}
  Example: feat(auth): add SSO login support"
fi

# Check scope requirement
if [[ "$SCOPE_REQUIRED" == "true" ]]; then
  if ! echo "$SUBJECT" | grep -qE "^[^(]+\([a-zA-Z]" 2>/dev/null; then
    output_block "[git-pilot] Commit message format error:
  Expected: ${COMMIT_PATTERN}
  Got: ${SUBJECT}
  Issue: scope is required but was not provided
  Example: feat(auth): add SSO login support"
  fi
fi

# --- Body policy ---
BODY_REQUIRED=$(echo "$CONFIG" | jq -r '.commit.body.required // false')
IS_BREAKING=false
if [[ "$SUBJECT" =~ !: ]]; then
  IS_BREAKING=true
fi

# Detect if a body is present
HAS_BODY=false
if [[ "$COMMIT_MSG" == *$'\n'* ]]; then
  BODY_TEXT=$(echo "$COMMIT_MSG" | tail -n +2 | sed '/^$/d')
  if [[ -n "$BODY_TEXT" ]]; then
    HAS_BODY=true
  fi
fi

# Reject body when body.required is false and commit is not a breaking change
if [[ "$BODY_REQUIRED" == "false" ]] && [[ "$HAS_BODY" == "true" ]] && [[ "$IS_BREAKING" == "false" ]]; then
  output_block "[git-pilot] Commit body is not allowed (commit.body.required is false). Use subject-line only unless it's a breaking change."
fi

if [[ "$IS_BREAKING" == true ]]; then
  REQUIRE_BODY=$(echo "$CONFIG" | jq -r '.commit.breakingChange.requireBody // true')
  BODY_PREFIX=$(echo "$CONFIG" | jq -r '.commit.breakingChange.bodyPrefix // "BREAKING CHANGE: "')

  if [[ "$REQUIRE_BODY" == "true" ]]; then
    # Check if there is a body (lines after the subject, skipping a blank line)
    BODY=""
    if [[ "$COMMIT_MSG" == *$'\n'* ]]; then
      BODY=$(echo "$COMMIT_MSG" | tail -n +2 | sed '/^$/d' | head -n 1)
    fi

    if [[ -z "$BODY" ]]; then
      output_block "[git-pilot] Breaking changes require a commit body starting with '${BODY_PREFIX}'."
    fi

    if [[ "$BODY" != "$BODY_PREFIX"* ]]; then
      output_block "[git-pilot] Breaking changes require a commit body starting with '${BODY_PREFIX}'."
    fi
  fi
fi

# --- Signature stripping ---
STRIPPED_MSG=""
SYSTEM_MSG=""

# Check branch protection
protect_mode=$(get_config "$CONFIG" '.git.protectDefaultBranch' 'warn')
protect_mode=$(normalize_protect_default_branch "$protect_mode")
if is_on_default_branch "$CONFIG" 2>/dev/null; then
  default_br=$(get_default_branch "$CONFIG")
  case "$protect_mode" in
    warn)
      SYSTEM_MSG="[git-pilot] Warning: You are committing directly to '${default_br}'. Consider creating a feature branch first."
      ;;
    block)
      output_block "[git-pilot] Commits to '${default_br}' are blocked by policy (git.protectDefaultBranch: block). Create a feature branch first using /branch."
      ;;
    off)
      ;;
  esac
fi

if strip_signatures "$CONFIG" "$COMMIT_MSG"; then
  # Message was modified — rebuild the command
  NEW_COMMAND=$(rebuild_commit_command "$COMMAND" "$STRIPPED_MSG")
  if [[ -n "$SYSTEM_MSG" ]]; then
    output_allow_with_message_and_updated_input "$SYSTEM_MSG" "$NEW_COMMAND"
  else
    output_allow_with_updated_input "$NEW_COMMAND"
  fi
fi

# No modification needed
if [[ -n "$SYSTEM_MSG" ]]; then
  output_allow_with_message "$SYSTEM_MSG"
fi

output_allow
