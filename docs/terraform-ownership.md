# Terraform Ownership Boundaries

## Terraform/OpenTofu Owns

- Cloudflare DNS records for selected public services
- Tailscale policy/grants when explicitly enabled
- Infra metadata and exposure classification stored in `infra/terraform/data`

## Terraform/OpenTofu Does Not Own

- Local Docker container lifecycle
- Router/firewall configuration unless an API-backed integration is added later
- Application config rendered under `C:\docker`
- Secrets themselves

## Adoption Rules

1. Start with a small set of public DNS records.
2. Import existing records before modifying them.
3. Avoid mixed dashboard/manual edits for Terraform-owned records.
4. Keep metadata files updated even for resources not yet fully managed.

## Initial Target Resources

- `ntfy.aahmed.ca`
- `wazuh.aahmed.ca`
- `homefiles.aahmed.ca`
- future platform hostnames such as `secrets.home.aahmed.ca`
