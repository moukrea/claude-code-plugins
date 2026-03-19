---
paths:
  - "**/terraform/**"
  - "**/*.tf"
  - "**/docker-compose*"
  - "**/Dockerfile*"
  - "**/k8s/**"
---

# Infrastructure Rules
- ALWAYS run `terraform plan` before `terraform apply`
- NEVER put secrets or credentials in infrastructure files
- Use variables for all configurable values
- Validate Dockerfiles with `hadolint` if available
- For Kubernetes, validate manifests with `kubectl --dry-run=client`
