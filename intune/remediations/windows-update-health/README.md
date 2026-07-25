# Windows Update Health Remediation for Microsoft Intune

A conservative Microsoft Intune Remediations pair for Windows Update client health.

This is **not** a direct clone of `mertozsoy/WindowsUpdateRemedationTool`. The upstream tool is useful as an interactive break-fix GUI, but several actions are too broad for automatic enterprise rollout. This rebuild keeps the useful operational idea and changes the execution model for Intune: read-only detection, conservative remediation, clear logs, no runtime binary download, no policy deletion, no forced restart.

## What problem this solves

Windows devices sometimes stop scanning or installing updates because local update services are stopped/disabled, BITS queue files are stale, or local Windows Update cache folders are missing/corrupted. This tool gives endpoint admins a repeatable first-line repair before opening deeper device investigation.

## Scripts

| File | Intune role | Default behavior |
|---|---|---|
| `Detect-WindowsUpdateHealth.ps1` | Detection | Read-only checks for service health, stale BITS queue, cache folder presence, paused-update indicators, pending reboot, and hotfix age warning. |
| `Remediate-WindowsUpdateHealth.ps1` | Remediation | Starts/corrects required services, removes stale BITS queue files, ensures SoftwareDistribution exists, optional scan trigger. |

## Why not run the upstream GUI as-is in an org?

The upstream script performs powerful local repair actions:

- deletes `HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`
- changes Windows Update pause/defer and telemetry-related registry values
- stops `BITS`, `wuauserv`, and `cryptsvc`
- deletes `SoftwareDistribution` and `Catroot2`
- resets BITS/WUA service security descriptors using `sc.exe sdset`
- re-registers many DLLs with `regsvr32.exe`
- runs `netsh winsock reset`
- downloads `SetupDiag.exe` at runtime
- prompts for restart

Those actions can be acceptable for **manual break-fix on one approved device**, but they are not safe defaults for a managed environment because they can conflict with Intune, Windows Update for Business, Group Policy, security baselines, change control, and privacy/telemetry policy ownership.

## Enterprise safety posture

Safe for pilot use when deployed like this:

- Run as **System** in Microsoft Intune Remediations.
- Run in **64-bit PowerShell**.
- Assign to a small pilot group first.
- Keep the default remediation level `Conservative`.
- Review `C:\MK-LogFiles\Detect-WindowsUpdateHealth.log` and `C:\MK-LogFiles\Remediate-WindowsUpdateHealth.log`.
- Use Intune update rings, expedited quality updates, or Windows Autopatch for actual patch compliance. This script repairs the local update client; it does not replace update policy.

Not recommended as a broad automatic action:

- deleting policy registry keys
- resetting service security descriptors
- deleting `Catroot2` automatically
- forcing restarts
- changing telemetry policy
- downloading executable repair tools at runtime

## Intune setup

1. Go to **Microsoft Intune admin center** > **Devices** > **Scripts and remediations** > **Remediations**.
2. Create a remediation package.
3. Upload:
   - Detection script: `Detect-WindowsUpdateHealth.ps1`
   - Remediation script: `Remediate-WindowsUpdateHealth.ps1`
4. Settings:
   - Run this script using logged-on credentials: **No**
   - Enforce script signature check: according to your signing process
   - Run script in 64-bit PowerShell: **Yes**
5. Assign to a pilot group first.
6. Review logs and Intune remediation output before wider rollout.

## Optional local testing

Detection only:

```powershell
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\Detect-WindowsUpdateHealth.ps1
```

Dry-run remediation:

```powershell
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remediate-WindowsUpdateHealth.ps1 -DryRun
```

Conservative remediation with scan trigger:

```powershell
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remediate-WindowsUpdateHealth.ps1 -TriggerScan
```

Explicit cache reset for approved break-fix only:

```powershell
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remediate-WindowsUpdateHealth.ps1 -RepairLevel CacheReset
```

## Rollback

Default conservative remediation has limited rollback need because it starts services and removes stale BITS queue files only. For `CacheReset`, the script renames cache folders to timestamped `.bak-YYYYMMDD-HHMMSS` folders instead of deleting them. If needed, stop update services and restore the renamed folders before restarting services.

## Release tracking

- Version is declared in each script header.
- Commit SHA and branch should be recorded in the Intune remediation package description.
- Use `docs/RELEASE-CHECKLIST.md` before broad rollout.
- Optional KQL/reporting starter is in `kql/windows-update-health-tracking.kql`.
