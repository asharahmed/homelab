# ATT&CK Navigator Coverage Layer

`homelab-coverage.json` is a [MITRE ATT&CK Navigator](https://mitre-attack.github.io/attack-navigator/)
layer generated from the `attack.tXXXX` tags on the Sigma rules in `../rules/`.
It is the one-page visual answer to "what does your detection coverage actually look like."

## What it shows

- **17 techniques** (10 base + 7 sub-techniques) across 8 ATT&CK tactics:
  Reconnaissance, Initial Access, Execution, Persistence, Defense Evasion,
  Credential Access, Discovery, and Command and Control.
- Each colored cell is backed by one or more rules. The **score is the highest
  severity** of the rules covering that technique (1 informational → 5 critical),
  rendered as a yellow→orange→red heatmap.
- Hover a cell in Navigator to see the rule filenames (stored in each technique's
  `metadata`).

## How to view it

1. Open <https://mitre-attack.github.io/attack-navigator/>.
2. **Open Existing Layer → Upload from local** and select `homelab-coverage.json`
   (or **Load from URL** if you've published the repo and point it at the raw file).
3. The matrix renders with covered techniques colored by severity.

To export a shareable image, use Navigator's **render-to-SVG** button (camera icon).
A committed `coverage.svg` makes the coverage visible directly in the repo README
without anyone needing to open Navigator.

## Regenerating

The layer is derived from rule tags. When you add or retag a rule, update the
matching technique entry here (or regenerate). Each entry needs:

```json
{
  "techniqueID": "T1059.001",
  "score": 5,
  "comment": "<rule title> — N rules, max severity <level>",
  "enabled": true,
  "metadata": [{ "name": "rules", "value": "<filename(s)>" }]
}
```

Severity → score: informational 1, low 2, medium 3, high 4, critical 5.
