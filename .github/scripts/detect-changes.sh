#!/usr/bin/env bash
set -euo pipefail

# Get changed files between previous and current commit
CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD)

# Extract unique plugin names from changed paths
CHANGED_PLUGINS=$(echo "$CHANGED_FILES" | \
  grep '^plugins/' | \
  cut -d'/' -f2 | \
  sort -u || true)

# Convert to JSON array
if [ -z "$CHANGED_PLUGINS" ]; then
  echo "[]"
else
  echo "$CHANGED_PLUGINS" | jq -R -s 'split("\n") | map(select(length > 0))'
fi
