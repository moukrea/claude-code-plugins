#!/usr/bin/env bash
set -euo pipefail

# Session state management for git-pilot.
# Provides functions to create, read, update, and clean up session state files.

# Returns the state file path for a given session ID.
get_state_file() {
  local session_id="$1"
  echo "/tmp/git-pilot-${session_id}.json"
}

# Reads the state file content. Returns {} if the file is missing or contains invalid JSON.
read_state() {
  local state_file="$1"
  if [[ -f "$state_file" ]]; then
    local content
    content=$(cat "$state_file")
    if echo "$content" | jq empty 2>/dev/null; then
      echo "$content"
    else
      echo "{}"
    fi
  else
    echo "{}"
  fi
}

# Atomically writes content to the state file using a temp file + mv pattern.
# Logs a warning and continues if the write fails.
write_state() {
  local state_file="$1"
  local content="$2"
  local tmp_file="${state_file}.tmp.$$"

  if ! echo "$content" > "$tmp_file"; then
    echo "[git-pilot] Warning: Cannot access session state. Auto-commit tracking disabled for this session." >&2
    rm -f "$tmp_file"
    return 0
  fi

  if ! mv "$tmp_file" "$state_file"; then
    echo "[git-pilot] Warning: Cannot access session state. Auto-commit tracking disabled for this session." >&2
    rm -f "$tmp_file"
    return 0
  fi
}

# Creates the initial session state file.
# Parameters: session_id, working_branch (optional), previous_branch (optional),
#             base_branch (optional), branch_purpose (optional).
init_state() {
  local session_id="$1" working_branch="${2:-}" previous_branch="${3:-}"
  local base_branch="${4:-}" branch_purpose="${5:-}"
  local state_file head_at_start=""
  state_file=$(get_state_file "$session_id")
  if command -v git >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
    head_at_start=$(git rev-parse HEAD 2>/dev/null || true)
  fi
  local content
  content=$(jq -n \
    --arg sid "$session_id" --arg start "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg wb "$working_branch" --arg pb "$previous_branch" \
    --arg head "$head_at_start" --arg bb "$base_branch" --arg bp "$branch_purpose" \
    '{ sessionId:$sid, startTime:$start, workingBranch:$wb, previousBranch:$pb,
       headAtStart:$head, baseBranch:$bb, branchPurpose:$bp, changeCount:0,
       lastCommitAt:null, modifiedFiles:[], remoteSkipped:false, lastFetchAt:null,
       isAgent:false, agentRole:null, activeWorktrees:[], stashRefs:[] }')
  write_state "$state_file" "$content"
}

# Reads the current state, applies a jq filter, and atomically writes back.
# Parameters: state_file, [jq_args...], jq_filter.
update_state() {
  local state_file="$1"; shift
  local current; current=$(read_state "$state_file")
  local updated; updated=$(echo "$current" | jq "$@")
  write_state "$state_file" "$updated"
}

# Removes the session state file.
cleanup_state() {
  local state_file="$1"
  rm -f "$state_file"
}
