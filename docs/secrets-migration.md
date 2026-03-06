# Secrets Migration

## Goals

- Remove long-lived sensitive values from repo-tracked files.
- Make secret rotation operationally cheap.
- Separate bootstrap-only local secrets from normal runtime secrets.

## Secret Classes

### bootstrap-only
- Self-hosted Infisical startup material
- Stays local on the host and outside git

### infra
- Cloudflare API tokens
- Tailscale API keys
- Terraform credentials

### runtime
- SMTP credentials
- bot tokens
- API keys
- webhook URLs
- CrowdSec / Wazuh / Blackbox secrets

## Migration Order

1. Edge and control-plane credentials
- Cloudflare
- Tailscale
- webhook tokens

2. Monitoring and security integrations
- Telegram
- SMTP
- CrowdSec
- Wazuh integration keys

3. Application API keys
- Arr stack
- media/automation service keys

## Delivery Model

1. Bootstrap Infisical locally with `bootstrap-infisical.ps1`
2. Push selected current `.env` secrets using `export-env-to-infisical.ps1`
3. Render runtime secrets using `render-secrets-from-infisical.ps1`
4. Update deploy/render scripts to consume generated runtime secrets instead of static `.env`

## Rules

- Never commit production secret values.
- Keep `.env.example` for non-secret defaults only.
- Keep `.env.bootstrap.local` for bootstrap-only values.
- Rotate any token that has already been exposed in terminal history or repo state.
