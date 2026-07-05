# Detection lifecycle (CI/CD)

Detection content ships through a gated pipeline, not by hand. This is the
"detection engineering" workflow: author vendor-agnostic Sigma, prove it in
CI, review it, and let CD deploy it to Sentinel/Defender on merge.

```
author Sigma ──▶ PR ──▶ Detections CI (offline gates) ──▶ review (CODEOWNERS)
     ▲                                                            │
     │                                                            ▼
 tune / retest ◀── validate (Atomic Red Team) ◀── CD deploy ◀── merge to main
```

## CI — `.github/workflows/detections-ci.yml`

Runs on every PR touching `detections/**`. No cloud credentials, so it works
on forks and untrusted PRs.

| Job | Gate |
|-----|------|
| `sigma-validate` | `sigma check` — structure + validators on all Windows and custom Sigma rules |
| `rules-in-sync` | Regenerates `analytics-rules.json` and fails if the committed artifact is stale (forces "regenerate before commit") |
| `bicep-validate` | `az bicep build` on every `detections/**/*.bicep` — fails on compile errors |
| `defender-schema` | Required-field + severity + non-empty-query validation on `custom-detections.json` |

## CD — `.github/workflows/detections-deploy.yml`

Runs on merge to `main` (and `workflow_dispatch`). Deploys the Sentinel
analytics rules (Bicep) and the Defender custom detections (Graph). Gated
behind a GitHub **`production` environment** so a human approves before the
live workspace is touched.

Auth is **Workload Identity Federation (OIDC)** for ARM — no Azure secret is
stored in GitHub. The Defender Graph app still uses client-credentials
(separate, non-ARM API) supplied as repo secrets.

### One-time setup

Repo secrets required: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID`, `DEFENDER_APP_ID`, `DEFENDER_APP_SECRET`.

```bash
# 1. App registration for GitHub OIDC
appId=$(az ad app create --display-name "github-detections-deployer" --query appId -o tsv)
az ad sp create --id "$appId"

# 2. Federated credential — trust this repo's 'production' environment
az ad app federated-credential create --id "$appId" --parameters '{
  "name": "github-prod",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:asharahmed/homelab_private:environment:production",
  "audiences": ["api://AzureADTokenExchange"]
}'

# 3. Least-privilege role: Sentinel Contributor on the RG only
spId=$(az ad sp show --id "$appId" --query id -o tsv)
az role assignment create --assignee "$spId" \
  --role "Microsoft Sentinel Contributor" \
  --scope "/subscriptions/<SUB_ID>/resourceGroups/rg-sentinel"
```

Then in GitHub: **Settings → Environments → new environment `production`** with
**Required reviewers**, and **Settings → Branches → protect `main`**: require a
PR, require the **Detections CI** checks to pass, and require CODEOWNERS review.

## Why this matters

This converts detection-as-code from "scripts a human runs" into a real
lifecycle: every rule is peer-reviewed, machine-validated, and deployed
identically every time — with an audit trail in Git and an approval gate on
production. That's the enterprise baseline for detection engineering.
