#!/usr/bin/env bash
set -euo pipefail

# Read JSON input from Claude Code
INPUT=$(cat)

# Extract the command being executed
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')

# Only intercept git commit commands
case "$CMD" in
    *git\ commit*|*git\ -[cC]\ *commit*) ;;
    *) exit 0 ;;
esac

# Determine which repo based on cwd
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""')

OPAQ_DIR="/home/eco/Code/Personal/opaq/opaq"
PLUGINS_DIR="/home/eco/Code/Personal/opaq/claude-code-plugins"

if [[ "$CWD" == "$OPAQ_DIR"* ]]; then
    # ── opaq Rust repo validation ──

    # Auto-fix formatting
    if ! cargo fmt --check --manifest-path "$OPAQ_DIR/Cargo.toml" >/dev/null 2>&1; then
        cargo fmt --manifest-path "$OPAQ_DIR/Cargo.toml"
        git -C "$OPAQ_DIR" add -u
        echo "[hook] Auto-fixed formatting with cargo fmt. Files re-staged." >&2
    fi

    # Clippy
    if ! cargo clippy --manifest-path "$OPAQ_DIR/Cargo.toml" --all-targets --features linux-keychain -- -D warnings 2>&1; then
        echo "[hook] Clippy errors found. Fix them before committing." >&2
        exit 2
    fi

    # Tests
    if ! cargo test --manifest-path "$OPAQ_DIR/Cargo.toml" --features linux-keychain 2>&1; then
        echo "[hook] Tests failed. Fix them before committing." >&2
        exit 2
    fi

    exit 0

elif [[ "$CWD" == "$PLUGINS_DIR"* ]]; then
    # ── claude-code-plugins validation ──

    if ! (cd "$PLUGINS_DIR" && .github/scripts/validate-plugins.sh) 2>&1; then
        echo "[hook] Plugin validation failed. Fix the issues before committing." >&2
        exit 2
    fi

    exit 0

else
    # Not one of our repos — allow
    exit 0
fi
