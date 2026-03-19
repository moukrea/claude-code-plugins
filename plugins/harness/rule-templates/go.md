---
paths:
  - "**/*.go"
---

# Go Rules
- Run `go vet` after changes for static analysis
- Run `golangci-lint run` if available
- Use `go test ./...` for full test suite
- Follow existing error handling patterns (check error returns)
- Use `gofmt` formatting (usually enforced by editor)
