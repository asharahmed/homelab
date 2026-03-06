# Rollout Plan

## Phase 1
- Add repo scaffolding for Terraform/OpenTofu, security tooling, and docs.
- Add dormant `platform` compose profile for Infisical.
- Add bootstrap/render/validation scripts.

## Phase 2
- Bootstrap and launch Infisical.
- Create project/folder structure and machine identity.
- Export first-wave secrets from the current `.env`.

## Phase 3
- Move deploy scripts to rendered runtime secrets.
- Validate Terraform/OpenTofu locally.
- Import first Cloudflare resources.

## Phase 4
- Enable scheduled Trivy scans.
- Add Renovate-driven update workflow.
- Tighten network policy using the documented zone matrix.

## Rollback

- Stop `platform` profile containers if Infisical bootstrap fails.
- Keep current `.env`-driven workflow intact until rendered runtime secrets are proven.
- Import Terraform resources incrementally to avoid ownership conflicts.
