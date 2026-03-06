# Terraform/OpenTofu Scaffold

This tree is intentionally limited to external control planes and infra metadata.

## Scope

- Cloudflare DNS records and public-service metadata
- Tailscale policy/grants when enabled
- Service/domain/network metadata stored in version control

## Usage

1. Copy `envs/prod/terraform.tfvars.example` to a local, ignored `terraform.tfvars`.
2. Set provider credentials through environment variables or a local vars file.
3. Run:

```powershell
.\scripts\validate-terraform.ps1
```

4. Start by importing a small set of existing DNS records before any apply.

## Tooling

- Preferred open source engine: `OpenTofu`
- Compatible fallback: `Terraform`
