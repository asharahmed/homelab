# Contributing — detection review gate

Every detection enters through a pull request. This is the peer-review step that separates engineered detections from ad-hoc alerts.

## Definition of done for a new rule

- [ ] One rule per file, named descriptively (`technique-behavior.yml`).
- [ ] Valid `id:` (UUID), `status:`, `description:`, `author:`, `date:`.
- [ ] Tagged with the relevant `attack.<tactic>` and `attack.t<technique>` tags.
- [ ] `falsepositives:` lists at least the known benign triggers (not "Unknown" unless truly none).
- [ ] `level:` set deliberately (`informational`→`critical`) and justified by impact.
- [ ] `sigma check rules/` passes locally.
- [ ] `sigma convert` produces sane SPL **and** KQL (paste the generated queries in the PR).
- [ ] Where feasible, an Atomic Red Team test number for the technique is referenced so the detection is exercised, not assumed.

## Review checklist (reviewer)

- Does the logic actually match the technique, or just a noisy proxy?
- Is the false-positive surface acceptable for the stated `level`?
- Could an attacker trivially evade it (e.g. case, encoding, alternate LOLBin)?
- Are field names correct for the declared `logsource` (will it convert)?

## Tuning

False positives are tracked as issues and resolved by refining `falsepositives:` and the selection logic — not by deleting the rule. A detection's history (PRs, tuning commits) is itself the evidence of engineering rigor.
