#!/bin/sh
set -e

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

echo "=== Smoke test ==="
PLUGIN_ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$PLUGIN_ROOT/scripts/claude-switcher.sh" ]; then
    sh "$PLUGIN_ROOT/scripts/claude-switcher.sh" --help >/dev/null 2>&1 && echo "CLI: ok" || echo "CLI: not ready yet"
else
    echo "CLI: not built yet"
fi

echo "=== CLI symlink ==="
mkdir -p "$HOME/.claude-switcher"
ln -sf "$PLUGIN_ROOT/scripts/claude-switcher.sh" "$HOME/.claude-switcher/cli"
echo "Linked ~/.claude-switcher/cli"

echo "=== Ready ==="
