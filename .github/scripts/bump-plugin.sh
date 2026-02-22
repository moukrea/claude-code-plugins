#!/usr/bin/env bash
set -euo pipefail

PLUGIN="$1"

# Get current version from plugin.json
CURRENT_VERSION=$(jq -r '.version' "plugins/$PLUGIN/.claude-plugin/plugin.json")

# Analyze conventional commits touching this plugin
COMMITS=$(git log --format="%s" HEAD~1..HEAD -- "plugins/$PLUGIN/")

# Determine bump level
BUMP="none"
while IFS= read -r MSG; do
  [ -z "$MSG" ] && continue
  if echo "$MSG" | grep -qE 'BREAKING CHANGE:|^[a-z]+(\(.*\))?!:'; then
    BUMP="major"
    break
  elif echo "$MSG" | grep -qE '^feat(\(.*\))?:'; then
    [ "$BUMP" != "major" ] && BUMP="minor"
  elif echo "$MSG" | grep -qE '^(fix|perf)(\(.*\))?:'; then
    [ "$BUMP" = "none" ] && BUMP="patch"
  fi
done <<< "$COMMITS"

if [ "$BUMP" = "none" ]; then
  echo "No version-bumping commits for $PLUGIN, skipping"
  exit 0
fi

# Parse current version
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Calculate new version
case "$BUMP" in
  major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
  minor) NEW_VERSION="$MAJOR.$((MINOR + 1)).0" ;;
  patch) NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
esac

echo "Bumping $PLUGIN: $CURRENT_VERSION -> $NEW_VERSION ($BUMP)"

# Update plugin.json version
jq --arg v "$NEW_VERSION" '.version = $v' \
  "plugins/$PLUGIN/.claude-plugin/plugin.json" > tmp.json && \
  mv tmp.json "plugins/$PLUGIN/.claude-plugin/plugin.json"

# Update marketplace.json entry for this plugin
jq --arg name "$PLUGIN" --arg v "$NEW_VERSION" \
  '(.plugins[] | select(.name == $name)).version = $v' \
  .claude-plugin/marketplace.json > tmp.json && \
  mv tmp.json .claude-plugin/marketplace.json

# Output the new version for the workflow to use
echo "NEW_VERSION=$NEW_VERSION" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "PLUGIN_NAME=$PLUGIN" >> "${GITHUB_OUTPUT:-/dev/null}"
