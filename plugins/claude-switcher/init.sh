#!/bin/sh
set -e

# claude-switcher plugin init
# Runs when the plugin is loaded by Claude Code.
# Creates CLI symlink and installs status line helpers.

echo "=== Prerequisites ==="
if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq required but not installed"
    if command -v apt >/dev/null 2>&1; then
        echo "  Install: sudo apt install jq"
    elif command -v brew >/dev/null 2>&1; then
        echo "  Install: brew install jq"
    elif command -v dnf >/dev/null 2>&1; then
        echo "  Install: sudo dnf install jq"
    elif command -v pacman >/dev/null 2>&1; then
        echo "  Install: sudo pacman -S jq"
    fi
    exit 1
fi
echo "jq $(jq --version)"

PLUGIN_ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "=== Smoke test ==="
if [ -f "$PLUGIN_ROOT/scripts/claude-switcher.sh" ]; then
    sh "$PLUGIN_ROOT/scripts/claude-switcher.sh" help >/dev/null 2>&1 && echo "CLI: ok" || echo "CLI: warning, help failed"
else
    echo "CLI: scripts not found at $PLUGIN_ROOT/scripts/"
    exit 1
fi

echo "=== CLI symlink ==="
mkdir -p "$HOME/.claude-switcher"
ln -sf "$PLUGIN_ROOT/scripts/claude-switcher.sh" "$HOME/.claude-switcher/cli"
echo "Linked ~/.claude-switcher/cli -> $PLUGIN_ROOT/scripts/claude-switcher.sh"

echo "=== Status line helpers ==="
sh "$PLUGIN_ROOT/scripts/claude-switcher.sh" setup-plugin 2>&1 || echo "warning: setup-plugin had issues (non-fatal)"

echo "=== Ready ==="
