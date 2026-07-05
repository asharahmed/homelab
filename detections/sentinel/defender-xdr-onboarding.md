# Defender XDR → Sentinel onboarding runbook

Brings real EDR telemetry to the deployed Sentinel analytics rules. The 5 rules
in `analytics-rules.json` query Defender XDR `Device*` tables; this runbook
provisions Defender for Endpoint, onboards a host, and streams those tables into
the `law-homelab` workspace so the rules fire on live data.

## Why parts of this are portal steps, not code

The deployable layer (workspace, Sentinel, analytics rules, budget) is Bicep in
this directory. But two things are **not** exposed in the stable ARM schema and
must be done in the portal:

- **Defender for Endpoint licensing/provisioning** — licensed via Microsoft 365,
  not the Azure subscription. Started as a trial in the admin/Defender portal.
- **The Microsoft Defender XDR connector's raw event streaming** ("Connect
  events") — the `MicrosoftThreatProtection` connector kind and its `Device*`
  table streaming are not in the stable `Microsoft.SecurityInsights/dataConnectors`
  schema, so they're configured in the Sentinel/Defender portal UI.

Everything else stays as code. Each manual step below notes who does it.

---

## Step 1 — Start the Defender for Endpoint trial  *(you · portal · free)*

Requires **Global Administrator** on the tenant (`asharasharahmed.onmicrosoft.com`).
The Defender for Endpoint trial is free and does **not** require a credit card —
if a step asks for payment, you're on the wrong SKU; back out and pick the
*Defender for Endpoint* trial.

1. Go to **https://security.microsoft.com** (Microsoft Defender portal).
2. In the left nav open **Assets → Devices** (or **Settings → Endpoints**). If
   MDE isn't provisioned yet, the portal prompts to **start a trial / set up** —
   accept it. (Alternative: **https://admin.microsoft.com → Billing → Purchase
   services → Free trials → Microsoft Defender for Endpoint**.)
3. Wait for provisioning to finish (a few minutes; the Endpoints settings pages
   become available).
4. Assign the trial license to your admin user in **admin.microsoft.com → Users**
   so advanced hunting / portal features work fully.

**Done when:** `security.microsoft.com → Settings → Endpoints → Onboarding`
loads and offers onboarding packages.

## Step 2 — Onboard this host to MDE  *(you · portal + run on host)*

1. In **Defender portal → Settings → Endpoints → Onboarding**:
   - Operating system: **Windows 10 and 11**
   - Deployment method: **Local Script** (fine for a single lab host)
   - **Download onboarding package** (a .zip containing
     `WindowsDefenderATPLocalOnboardingScript.cmd`).
2. On this host, run the script **as Administrator**:
   ```powershell
   # from the extracted package folder, in an elevated shell
   .\WindowsDefenderATPLocalOnboardingScript.cmd
   ```
3. Confirm the sensor is reporting — run the official detection test (elevated):
   ```powershell
   powershell.exe -NoExit -ExecutionPolicy Bypass -WindowStyle Hidden `
     "$f='C:\test-MDATP-test\invoice.exe'; New-Item -ItemType Directory -Force 'C:\test-MDATP-test' | Out-Null; `
      Invoke-WebRequest 'http://localhost/' -OutFile $f; Start-Process $f"
   ```
   (Microsoft's canonical test command — generates a benign detection.)

**Done when:** the host appears in **Defender portal → Assets → Devices** (can
take ~15 min for first telemetry).

## Step 3 — Connect Defender XDR to Sentinel + stream events  *(you · portal)*

1. In **Microsoft Sentinel** (portal.azure.com → your `law-homelab` workspace →
   or the unified Defender portal) open **Configuration → Data connectors**.
2. Find **Microsoft Defender XDR** → **Open connector page**.
3. Under **Connect incidents & alerts** → **Connect** (brings MDE incidents/alerts
   into Sentinel as incidents).
4. Under **Connect events**, enable the Microsoft Defender for Endpoint event
   tables the rules need — at minimum:
   - `DeviceProcessEvents`  (PowerShell, Office-spawn rules)
   - `DeviceNetworkEvents`  (LOLBin network rule)
   - `DeviceFileEvents`     (payload-drop rule)
   - `DeviceRegistryEvents` (autostart-persistence rule)
   Then **Apply Changes**.

**Done when:** `DeviceProcessEvents | take 1` returns rows in the workspace's
**Logs** blade (telemetry can take 15–30 min to first appear).

## Step 4 — Validate end-to-end  *(me · CLI + you · run atomic)*

Once events are flowing:

1. I confirm the tables exist and have data (`az monitor log-analytics query`).
2. Run a mapped Atomic Red Team test on this host — e.g. T1059.001:
   ```powershell
   Invoke-AtomicTest T1059.001 -TestNumbers 15   # -EncodedCommand
   ```
   (see `docs/atomic-red-team-coverage.md`).
3. Confirm the **PowerShell Encoded or Download Command** rule fires and raises an
   incident in Sentinel, with the host entity populated.

That closes the loop: **detect (Sigma) → deploy (Bicep) → stream (Defender XDR) →
fire (Atomic) → incident.**

---

## Cost & cleanup

- MDE trial is free for its window. Event streaming into Sentinel is metered by
  GB — `Device*` tables on one lab host are low-volume, but watch the budget
  (`budget.bicep`, alerts at 80/100%). Filter with DCRs if it climbs.
- **Offboard the host** later via **Defender portal → Settings → Endpoints →
  Offboarding** (runs an offboarding script). Disconnect the connector to stop
  ingestion.
