# Homelab Security Operations workbook

A Microsoft Sentinel **workbook deployed as code** — the capstone dashboard
that shows the detection stack working in one pane: incidents, alerts by
ATT&CK tactic and by detection, and threat-intelligence feed health across
all three feeds.

## Files

| File | Purpose |
|------|---------|
| `workbook-content.json` | The workbook definition (Azure Monitor Workbook schema). Reviewable in Git. |
| `workbook.bicep` | Deploys it as a `Microsoft.Insights/workbooks` resource, embedding the JSON via `loadTextContent()`. Deterministic GUID name → redeploys update in place. |

## Tiles

- **Overview** — incidents, open incidents, alerts, TI indicators (stat tiles)
- **Detections firing** — alerts by ATT&CK tactic (bar) + alerts by detection with severity (grid)
- **Incidents** — over time by severity (bar) + by severity & status (grid)
- **Threat intelligence** — indicators by feed (pie: MDTI / OTX / abuse.ch) + top indicator types (bar)

All query tiles bind to the workbook time-range parameter via
`timeContextFromParameter`.

## Deploy

```powershell
az deployment group create -g rg-sentinel `
  --template-file workbook.bicep --parameters workspaceName=law-homelab
```

Then open **Microsoft Sentinel -> Workbooks -> My workbooks -> Homelab
Security Operations**.

## Notes

- Content is kept **ASCII-only** on purpose: the Windows `az` CLI renders
  `serializedData` through a cp1252 console and fails on emoji / `->` arrows
  during deployment. Portal rendering is unaffected.
- Data sources: `SecurityIncident`, `SecurityAlert` (Defender XDR alerts sync
  here), `ThreatIntelIndicators` (the current TI table — not the deprecated
  `ThreatIntelligenceIndicator`).
