#!/usr/bin/env bash
set -euo pipefail

# Git utility functions for git-pilot plugin.
# Sourced by hook scripts — do not set SCRIPT_DIR/PLUGIN_ROOT here.

is_git_repo() {
  git rev-parse --git-dir >/dev/null 2>&1
}

get_current_branch() {
  git branch --show-current 2>/dev/null
}

has_uncommitted_changes() {
  [[ -n "$(git status --porcelain 2>/dev/null)" ]]
}

get_default_branch() {
  local config="$1"
  echo "$config" | jq -r '.git.defaultBranch // "main"'
}

is_on_default_branch() {
  local config="$1"
  local current default_branch
  current=$(get_current_branch)
  default_branch=$(get_default_branch "$config")
  [[ "$current" == "$default_branch" ]]
}

has_remote() {
  [[ -n "$(git remote 2>/dev/null)" ]]
}

sanitize_branch_name() {
  local name="$1"
  echo "$name" | sed 's/[^a-zA-Z0-9._/-]//g'
}
