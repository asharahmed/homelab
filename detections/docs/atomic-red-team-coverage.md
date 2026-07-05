# Atomic Red Team coverage matrix

Each detection is tied to a runnable [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team)
test (or, where no atomic fits, a concrete manual procedure) so detections are **tested, not
assumed**. Run the atomic, confirm the rule's compiled query fires, record the result.

> ⚠️ **Run only in an isolated lab.** These execute real attack techniques (LSASS dumps, process
> injection, registry persistence, privileged containers). Never run against production or a
> daily-driver host. Use `-GetPrereqs` first and `-Cleanup` after.

> **Test numbers are version-dependent.** They were verified against the upstream `master`
> atomics as of 2026-06-29. Before running, confirm with
> `Invoke-AtomicTest T#### -ShowDetailsBrief`.

## Windows endpoint (direct atomic coverage)

| Rule | Technique | Atomic test(s) | Run | Expected |
|---|---|---|---|---|
| office_browser_spawns_lolbin | T1566.001 | #2 *Word spawned a command shell and used an IP address in the command line* | `Invoke-AtomicTest T1566.001 -TestNumbers 2` | Word→cmd child process; rule matches ParentImage winword + Image cmd |
| powershell_encoded_or_download | T1059.001 | #15 *-EncodedCommand parameter variations*; #1 *Mimikatz* (download cradle) | `Invoke-AtomicTest T1059.001 -TestNumbers 15` | `-encodedcommand` in CommandLine matches |
| lolbin_network_connection | T1105 | #7 *certutil download (urlcache)* | `Invoke-AtomicTest T1105 -TestNumbers 7` | certutil.exe makes outbound connection; rule matches Image certutil |
| unsigned_dll_from_user_writable_path | T1055.001 | #1 *Process Injection via mavinject.exe* | `Invoke-AtomicTest T1055.001 -TestNumbers 1` | unsigned `T1055.001.dll` loaded from temp; matches Signed=false + path |
| lsass_credential_access | T1003.001 | #2 *Dump LSASS.exe Memory using comsvcs.dll*; #1 *ProcDump*; #9 | `Invoke-AtomicTest T1003.001 -TestNumbers 2` | handle opened to lsass.exe; rule matches TargetImage lsass |
| remote_thread_injection | T1055 | #2 *Remote Process Injection in LSASS via mimikatz*; #9 *CreateRemoteThread WinAPI* | `Invoke-AtomicTest T1055 -TestNumbers 2` | remote thread into lsass; matches TargetImage lsass |
| registry_run_key_persistence | T1547.001 | #1 *Reg Key Run* (HKCU); #16 *secedit … Run key* (HKLM) | `Invoke-AtomicTest T1547.001 -TestNumbers 1` | write to CurrentVersion\Run; matches TargetObject |
| dns_query_suspicious_tld | T1071.004 | #1 *DNS Large Query Volume* (set the domain param to a `.xyz`/`.ru` value) | `Invoke-AtomicTest T1071.004 -TestNumbers 1 -InputArgs @{domain='example.ru'}` | DNS query to suspicious TLD; matches QueryName endswith |
| c2_named_pipe | T1071 | *No direct atomic.* Manual — see below | — | named pipe with C2-default name created |

### Manual validation — c2_named_pipe

No atomic creates a Cobalt-Strike/Meterpreter-style pipe. Two options:

```powershell
# Quick synthetic trigger (creates a pipe whose name matches the rule)
$p = New-Object System.IO.Pipes.NamedPipeServerStream('msagent_test')
# Sysmon EID 17 (PipeCreated) fires → rule matches PipeName contains 'msagent'
$p.Dispose()
```
Or run an actual C2 framework (Sliver/Havoc/Cobalt Strike) in the isolated lab and observe the
default pipe — higher fidelity, closer to the real detection scenario.

## Containers (direct atomic coverage)

| Rule | Technique | Atomic test(s) | Run | Expected |
|---|---|---|---|---|
| docker_privileged_container_start | T1611 | #2 *Mount host filesystem to escape privileged Docker container* | `Invoke-AtomicTest T1611 -TestNumbers 2` | privileged container start; matches privileged=true |
| docker_container_exec | T1609 | #2 *Docker Exec Into Container* | `Invoke-AtomicTest T1609 -TestNumbers 2` | `docker exec` event; matches Action=exec_start |

Minimal direct trigger for the privileged rule (no module needed):
```bash
docker run --privileged --rm alpine id   # daemon emits container start, privileged=true
```

## Custom log sources (manual validation — no fitting atomic)

Atomic Red Team has no tests for reverse-proxy / Authelia / OpenWrt log behaviors, so these are
validated with direct procedures against the lab:

| Rule | Technique | Manual procedure |
|---|---|---|
| caddy_sensitive_path_probe | T1595.003 | `curl -k https://<svc>.home.aahmed.ca/.env` (also `.git/config`, `/.aws/credentials`) |
| caddy_4xx_scanner_burst | T1595 | `for i in $(seq 1 15); do curl -k -o /dev/null https://<svc>.home.aahmed.ca/nope$i; done` — or `ffuf`/`gobuster` |
| caddy_credential_stuffing | T1110 | POST bad credentials to Authelia 8+ times from one IP (loop or `hydra http-post-form`) → 401/403 burst |
| caddy_bypass_token_header | T1078 | `curl -k -H "X-Bypass-Token: probe" https://<svc>.home.aahmed.ca/` |
| authelia_1fa_bruteforce | T1110.001 | 5+ failed password logins in 5 min from one IP (`hydra` or a login loop) |
| authelia_totp_bruteforce | T1110.001 | 3+ failed TOTP submissions in 5 min |
| router_ssh_bruteforce | T1110.001 | `hydra -l root -P wordlist.txt ssh://<router-ip>` (lab router only) |
| router_ssh_login_success | T1078 | one successful SSH login to the router after the brute-force run |

## Running the Windows + container atomics

```powershell
# One-time: install the execution framework + atomics
Install-Module -Name invoke-atomicredteam -Scope CurrentUser
Import-Module invoke-atomicredteam

# Per test: fetch prereqs, run, then clean up
Invoke-AtomicTest T1003.001 -TestNumbers 2 -GetPrereqs
Invoke-AtomicTest T1003.001 -TestNumbers 2
Invoke-AtomicTest T1003.001 -TestNumbers 2 -Cleanup
```

Or use `scripts/run-atomics.ps1`, which runs the mapped set with prereq-fetch and cleanup.

## Coverage summary

- **11 / 19** detections have a **direct** Atomic Red Team test (8 Windows endpoint + 1 cross-mapped via T1105 + 2 container).
- **1** (c2_named_pipe) has a documented synthetic/manual trigger.
- **8** custom-source detections (web / auth / network-device) have concrete manual procedures.

Every detection now has a defined way to prove it fires — the basis of a purple-team validation
loop and a coverage report you can show against MITRE ATT&CK.

## Automated validation loop

`detections/validation/validate-detections.ps1` closes this loop: it runs the
mapped atomic (with `-RunAtomics`) and then **auto-confirms** each detection has
visibility via advanced hunting, emitting `results/latest.json` and an ATT&CK
Navigator coverage layer (`coverage-layer.json`). Verify-only mode runs on a
weekly schedule (`schedule-validation.ps1`) to catch coverage drift. See
`detections/validation/README.md`.
