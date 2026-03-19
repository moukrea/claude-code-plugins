# Shared project-detection helpers for harness hooks
# Source this at the top of each hook script:
#   source "$(dirname "$0")/lib/detect.sh" 2>/dev/null || true
#
# Functions:
#   detect_project_type   # "Node.js (TypeScript)", "Rust", "Go", "Python", etc.
#   detect_test_cmd       # "npm test", "cargo test", "go test ./...", etc.
#   detect_lint_cmd       # "npm run lint", "cargo clippy", etc.
#   detect_build_cmd      # "npm run build", "cargo build", "go build ./...", etc.
#
# Each function prints a command string to stdout and returns 0.
# If nothing is detected, it prints nothing and still returns 0.

detect_project_type() {
  if [[ -f "package.json" ]]; then
    if [[ -f "tsconfig.json" ]]; then
      echo "Node.js (TypeScript)"
    else
      echo "Node.js"
    fi
    return
  elif [[ -f "Cargo.toml" ]]; then
    echo "Rust"; return
  elif [[ -f "go.mod" ]]; then
    echo "Go"; return
  elif [[ -f "pyproject.toml" || -f "setup.py" ]]; then
    echo "Python"; return
  elif [[ -f "Makefile" ]]; then
    echo "Make-based"; return
  fi
  return 0
}

detect_test_cmd() {
  if [[ -f "package.json" ]] && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    echo "npm test"; return
  elif [[ -f "Cargo.toml" ]]; then
    echo "cargo test"; return
  elif [[ -f "go.mod" ]]; then
    echo "go test ./..."; return
  elif [[ -f "pyproject.toml" || -f "setup.py" ]]; then
    echo "pytest"; return
  elif [[ -f "Makefile" ]] && grep -q '^test:' Makefile 2>/dev/null; then
    echo "make test"; return
  fi
  return 0
}

detect_lint_cmd() {
  if [[ -f "package.json" ]] && jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
    echo "npm run lint"; return
  elif [[ -f "Cargo.toml" ]] && command -v cargo >/dev/null 2>&1; then
    echo "cargo clippy"; return
  elif [[ -f "go.mod" ]] && command -v golangci-lint >/dev/null 2>&1; then
    echo "golangci-lint run"; return
  elif [[ -f "pyproject.toml" || -f "setup.py" ]] && command -v ruff >/dev/null 2>&1; then
    echo "ruff check ."; return
  fi
  return 0
}

detect_build_cmd() {
  if [[ -f "package.json" ]] && jq -e '.scripts.build' package.json >/dev/null 2>&1; then
    echo "npm run build"; return
  elif [[ -f "Cargo.toml" ]]; then
    echo "cargo build"; return
  elif [[ -f "go.mod" ]]; then
    echo "go build ./..."; return
  elif [[ -f "Makefile" ]] && grep -q '^build:' Makefile 2>/dev/null; then
    echo "make build"; return
  fi
  return 0
}
