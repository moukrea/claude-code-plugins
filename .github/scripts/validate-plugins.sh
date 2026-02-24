#!/usr/bin/env bash
set -euo pipefail

# validate-plugins.sh — Validates plugin structure, JSON syntax, required fields,
# version consistency, shellcheck compliance, and SKILL.md frontmatter.
# Must be run from the claude-code-plugins/ repository root.

# ── Section 1: Validate marketplace.json ──────────────────────────────────────

echo "Validating marketplace.json..."

# Verify valid JSON
jq empty .claude-plugin/marketplace.json

# Check required fields exist
jq -e '.name' .claude-plugin/marketplace.json > /dev/null
jq -e '.owner' .claude-plugin/marketplace.json > /dev/null
jq -e '.metadata.version' .claude-plugin/marketplace.json > /dev/null
jq -e '.plugins | type == "array"' .claude-plugin/marketplace.json > /dev/null

# For each entry in plugins array, verify required fields
jq -e '.plugins[] | .name, .version, .description' .claude-plugin/marketplace.json > /dev/null

echo "marketplace.json is valid."

# ── Section 2: Validate each plugin directory ─────────────────────────────────

echo "Validating plugin directories..."

for PLUGIN_DIR in plugins/*/; do
  PLUGIN=$(basename "$PLUGIN_DIR")
  echo "  Checking plugin: $PLUGIN"

  # Verify valid JSON
  jq empty "plugins/$PLUGIN/.claude-plugin/plugin.json"

  # Check required fields: name, version, description
  jq -e '.name' "plugins/$PLUGIN/.claude-plugin/plugin.json" > /dev/null
  jq -e '.version' "plugins/$PLUGIN/.claude-plugin/plugin.json" > /dev/null
  jq -e '.description' "plugins/$PLUGIN/.claude-plugin/plugin.json" > /dev/null

  # Verify the plugin is listed in marketplace.json's plugins array
  FOUND=$(jq --arg name "$PLUGIN" '.plugins[] | select(.name == $name)' .claude-plugin/marketplace.json)
  if [ -z "$FOUND" ]; then
    echo "ERROR: Plugin '$PLUGIN' not found in marketplace.json" >&2
    exit 1
  fi

  # Verify version in plugin.json matches version in marketplace.json
  PLUGIN_VERSION=$(jq -r '.version' "plugins/$PLUGIN/.claude-plugin/plugin.json")
  MARKETPLACE_VERSION=$(jq -r --arg name "$PLUGIN" '.plugins[] | select(.name == $name) | .version' .claude-plugin/marketplace.json)
  if [ "$PLUGIN_VERSION" != "$MARKETPLACE_VERSION" ]; then
    echo "ERROR: Version mismatch for '$PLUGIN': plugin.json=$PLUGIN_VERSION, marketplace.json=$MARKETPLACE_VERSION" >&2
    exit 1
  fi
done

echo "All plugin directories are valid."

# ── Section 3: Lint shell scripts ─────────────────────────────────────────────

echo "Running shellcheck on plugin shell scripts..."

SH_FILES=$(find plugins/ -name '*.sh' -type f 2>/dev/null || true)
if [ -n "$SH_FILES" ]; then
  find plugins/ -name '*.sh' -type f -exec shellcheck --severity=warning {} +
  echo "All shell scripts passed shellcheck."
else
  echo "No shell scripts found under plugins/."
fi

# ── Section 4: Validate skill files ──────────────────────────────────────────

echo "Validating SKILL.md files..."

SKILL_FILES=$(find plugins/ -path '*/skills/*.md' -name 'SKILL.md' 2>/dev/null || true)
if [ -n "$SKILL_FILES" ]; then
  for SKILL_FILE in $SKILL_FILES; do
    # Verify file is non-empty
    if [ ! -s "$SKILL_FILE" ]; then
      echo "ERROR: Skill file is empty: $SKILL_FILE" >&2
      exit 1
    fi

    # Verify file starts with YAML frontmatter (--- delimiters)
    FIRST_LINE=$(head -n 1 "$SKILL_FILE")
    if [ "$FIRST_LINE" != "---" ]; then
      echo "ERROR: Skill file does not start with YAML frontmatter: $SKILL_FILE" >&2
      exit 1
    fi
  done
  echo "All SKILL.md files are valid."
else
  echo "No SKILL.md files found under plugins/."
fi

echo "All validations passed."
