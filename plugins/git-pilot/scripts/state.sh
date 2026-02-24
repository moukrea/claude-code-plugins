#!/usr/bin/env bash
set -euo pipefail

# Session state management for git-pilot.
# Provides functions to create, read, update, and clean up session state files.

# Returns the state file path for a given session ID.
get_state_file() {
  local session_id="$1"
  echo "/tmp/git-pilot-${session_id}.json"
}

# Reads the state file content. Returns {} if the file is missing or unreadable.
read_state() {
  local state_file="$1"
  if [ -f "$state_file" ]; then
    cat "$state_file"
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
# Parameters: session_id, working_branch (optional), previous_branch (optional).
init_state() {
  local session_id="$1"
  local working_branch="${2:-}"
  local previous_branch="${3:-}"
  local state_file
  state_file=$(get_state_file "$session_id")

  local content
  content=$(jq -n \
    --arg sid "$session_id" \
    --arg start "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg wb "$working_branch" \
    --arg pb "$previous_branch" \
    '{
      sessionId: $sid,
      startTime: $start,
      workingBranch: $wb,
      previousBranch: $pb,
      changeCount: 0,
      lastCommitAt: null,
      modifiedFiles: [],
      remoteSkipped: false
    }')

  write_state "$state_file" "$content"
}

# Reads the current state, applies a jq filter, and atomically writes back.
# Parameters: state_file, jq_filter.
update_state() {
  local state_file="$1"
  local jq_filter="$2"
  local current
  current=$(read_state "$state_file")
  local updated
  updated=$(echo "$current" | jq "$jq_filter")
  write_state "$state_file" "$updated"
}

# Removes the session state file.
cleanup_state() {
  local state_file="$1"
  rm -f "$state_file"
}
