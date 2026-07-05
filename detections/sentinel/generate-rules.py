#!/usr/bin/env python3
"""
Generate Microsoft Sentinel scheduled analytics rules from the Sigma library.

For each Windows rule that compiles under the microsoft_xdr pipeline, this
shells out to sigma-cli to produce KQL, reads the rule's own metadata (title,
description, level, ATT&CK technique tags) and emits analytics-rules.json — the
parameter file consumed by main.bicep.

The Sigma rule's `id` (already a UUID) becomes the Sentinel rule name, so
re-running this is idempotent: same rule -> same Sentinel resource.

Usage:
    python generate-rules.py                # uses `sigma` from PATH
    SIGMA=/path/to/sigma python generate-rules.py

Only rules/windows/ is processed. Custom-source rules (Caddy/Authelia/Docker/
router) target custom Sentinel tables and are out of scope for this generator.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

SIGMA = os.environ.get("SIGMA", "sigma")
HERE = Path(__file__).resolve().parent
RULES_DIR = HERE.parent / "rules" / "windows"
OUT_FILE = HERE / "analytics-rules.json"

# Sigma level -> Sentinel severity (Sentinel has no "Critical" enum value).
SEVERITY = {
    "informational": "Informational",
    "low": "Low",
    "medium": "Medium",
    "high": "High",
    "critical": "High",
}

# ATT&CK technique (incl. sub-techniques) -> Sentinel tactic enum.
# Primary tactic only; Sentinel accepts one tactic list per rule.
TECHNIQUE_TACTIC = {
    "t1003": "CredentialAccess",
    "t1055": "DefenseEvasion",
    "t1059": "Execution",
    "t1071": "CommandAndControl",
    "t1105": "CommandAndControl",
    "t1078": "DefenseEvasion",
    "t1110": "CredentialAccess",
    "t1547": "Persistence",
    "t1566": "InitialAccess",
    "t1595": "Reconnaissance",
    "t1609": "Execution",
    "t1611": "PrivilegeEscalation",
}


def compile_kql(rule_path: Path) -> str:
    """Return the KQL for a rule, or '' if it doesn't convert."""
    result = subprocess.run(
        [SIGMA, "convert", "-t", "kusto", "-p", "microsoft_xdr", str(rule_path)],
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def tactics_and_techniques(tags):
    """Derive Sentinel tactics and technique IDs from sigma attack.* tags.

    Sentinel's scheduled-rule schema exposes a flat `techniques` string[] (no
    separate subTechniques field), and the live API enforces PARENT IDs only —
    it rejects sub-technique notation like T1071.001 with "expected format
    'T####'". So sub-techniques are collapsed to their parent here; the full
    sub-technique precision is retained in the Sigma rules and the ATT&CK
    Navigator layer. Tactic is derived from the parent technique.
    """
    tactics, techniques = [], []
    for tag in tags or []:
        if not tag.startswith("attack.t"):
            continue
        tech = tag.split(".", 1)[1].upper()  # t1071.001 -> T1071.001
        parent = tech.split(".")[0]  # T1071.001 -> T1071
        if parent not in techniques:
            techniques.append(parent)
        tactic = TECHNIQUE_TACTIC.get(parent.lower())
        if tactic and tactic not in tactics:
            tactics.append(tactic)
    return tactics, techniques


def main():
    if not RULES_DIR.is_dir():
        sys.exit(f"rules dir not found: {RULES_DIR}")

    rules, skipped = [], []
    for rule_path in sorted(RULES_DIR.glob("*.yml")):
        meta = yaml.safe_load(rule_path.read_text(encoding="utf-8"))
        kql = compile_kql(rule_path)
        if not kql:
            skipped.append(rule_path.name)
            continue

        tactics, techniques = tactics_and_techniques(meta.get("tags"))
        rules.append(
            {
                "name": meta["id"],
                "displayName": meta["title"],
                "description": " ".join(meta.get("description", "").split()),
                "severity": SEVERITY.get(str(meta.get("level", "medium")).lower(), "Medium"),
                "query": kql,
                "queryFrequency": "PT1H",
                "queryPeriod": "PT1H",
                "triggerOperator": "GreaterThan",
                "triggerThreshold": 0,
                "tactics": tactics,
                "techniques": techniques,
                "sourceRule": rule_path.name,
            }
        )

    OUT_FILE.write_text(json.dumps({"rules": rules}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT_FILE.relative_to(HERE.parent)} — {len(rules)} rules")
    for r in rules:
        print(f"  + {r['sourceRule']:<45} {r['severity']:<13} {','.join(r['techniques'])}")
    if skipped:
        print(f"skipped {len(skipped)} (no microsoft_xdr table mapping):")
        for s in skipped:
            print(f"  - {s}")


if __name__ == "__main__":
    main()
