#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/log.sh" 2>/dev/null || true
harness_start_timer || true

# PostToolUse hook (matcher: Write|Edit, async) -- fast verification on edited files
# Performance target: < 3s

# Read stdin
INPUT=$(cat) || exit 0

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Extract file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -n "$FILE_PATH" ]] || exit 0

ERRORS=""

case "$FILE_PATH" in
  *.ts|*.tsx)
    if [[ -f "tsconfig.json" ]] && command -v npx >/dev/null 2>&1; then
      ERRORS=$(npx tsc --noEmit --pretty 2>&1 | head -20) || true
      # tsc outputs nothing on success
      if [[ -z "$ERRORS" ]]; then harness_log "post-edit" "clean"; exit 0; fi
    else
      harness_log "post-edit" "skip" "no tsc for $FILE_PATH"
      exit 0
    fi
    ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      ERRORS=$(ruff check "$FILE_PATH" 2>&1 | head -10) || true
      if [[ -z "$ERRORS" ]]; then harness_log "post-edit" "clean"; exit 0; fi
    elif command -v python3 >/dev/null 2>&1; then
      ERRORS=$(python3 -m py_compile "$FILE_PATH" 2>&1) || true
      if [[ -z "$ERRORS" ]]; then harness_log "post-edit" "clean"; exit 0; fi
    elif command -v python >/dev/null 2>&1; then
      ERRORS=$(python -m py_compile "$FILE_PATH" 2>&1) || true
      if [[ -z "$ERRORS" ]]; then harness_log "post-edit" "clean"; exit 0; fi
    else
      harness_log "post-edit" "skip" "no python checker for $FILE_PATH"
      exit 0
    fi
    ;;
  *.rs)
    # Skip: cargo check is slow, LSP handles it
    harness_log "post-edit" "skip" "rust files use LSP"
    exit 0
    ;;
  *.go)
    if command -v go >/dev/null 2>&1; then
      ERRORS=$(go vet "$FILE_PATH" 2>&1 | head -10) || true
      if [[ -z "$ERRORS" ]]; then harness_log "post-edit" "clean"; exit 0; fi
    else
      harness_log "post-edit" "skip" "no go for $FILE_PATH"
      exit 0
    fi
    ;;
  *.js|*.jsx)
    if command -v npx >/dev/null 2>&1; then
      # Check for eslint config
      HAS_ESLINT=false
      for cfg in .eslintrc .eslintrc.js .eslintrc.json .eslintrc.yml .eslintrc.yaml eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts; do
        [[ -f "$cfg" ]] && HAS_ESLINT=true && break
      done
      # Also check package.json for eslintConfig
      if [[ "$HAS_ESLINT" == "false" && -f "package.json" ]]; then
        jq -e '.eslintConfig' package.json >/dev/null 2>&1 && HAS_ESLINT=true
      fi
      if [[ "$HAS_ESLINT" == "true" ]]; then
        ERRORS=$(npx eslint "$FILE_PATH" --no-warn-ignored 2>&1 | head -10) || true
        if [[ -z "$ERRORS" ]]; then harness_log "post-edit" "clean"; exit 0; fi
      else
        harness_log "post-edit" "skip" "no eslint config for $FILE_PATH"
        exit 0
      fi
    else
      harness_log "post-edit" "skip" "no npx for $FILE_PATH"
      exit 0
    fi
    ;;
  *)
    # Unsupported file type
    harness_log "post-edit" "skip" "unsupported file type: $FILE_PATH"
    exit 0
    ;;
esac

# If we got here, there are errors
if [[ -n "$ERRORS" ]]; then
  BASENAME=$(basename "$FILE_PATH")
  ERROR_COUNT=$(echo "$ERRORS" | wc -l | tr -d ' ')
  harness_log "post-edit" "errors" "$BASENAME: ${ERROR_COUNT} error line(s)"
  jq -nc --arg ctx "Lint/type errors in $BASENAME:"$'\n'"$ERRORS" \
    '{"additionalContext": $ctx}'
fi
