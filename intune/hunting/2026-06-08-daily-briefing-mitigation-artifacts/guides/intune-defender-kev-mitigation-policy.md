# Intune guide - Defender KEV mitigation policy

Date: 2026-06-08

## Goal

Mitigate Defender KEV exposure from:

- CVE-2026-41091 - Defender Malware Protection Engine, fixed in `1.1.26040.8`.
- CVE-2026-45498 - Defender Antimalware Platform, fixed in `4.18.26040.7`.

The goal is to ensure Windows endpoints receive Defender engine/platform/security intelligence updates and to identify devices that are stale or unhealthy.

## Scope

Include:

- Windows endpoints managed by Intune.

Exclude:

- iPads/iOS.
- Android MFA-only devices.
- macOS/Linux, not used in Robel's environment.

## Part 1 - Create or verify Defender Antivirus update policy

1. Open **Microsoft Intune admin center**.
2. Go to **Endpoint security** > **Antivirus**.
3. Select **Create Policy**.
4. Configure:
   - **Platform:** Windows 10, Windows 11, and Windows Server.
   - **Profile:** Microsoft Defender Antivirus.
5. Name:
   - `MK-Defender-AV-Update-Health-Baseline`
6. Recommended settings:
   - **Allow real-time monitoring:** Enabled.
   - **Allow cloud protection:** Enabled.
   - **Cloud-delivered protection level:** High or High plus if already tested.
   - **Submit samples consent:** Send safe samples automatically, if approved by policy.
   - **Check for security intelligence updates before running scan:** Enabled.
   - **Signature update interval:** 4 hours, or your existing municipal baseline.
   - **Signature update fallback order:** MicrosoftUpdateServer | MMPC | InternalDefinitionUpdateServer if you use internal sources.
7. Assign first to a pilot group:
   - Admin devices.
   - IT/Security devices.
   - A small HP model mix.
8. After 24 hours, expand to all Windows endpoints if no update failures appear.

## Part 2 - Add proactive remediation for version compliance

1. Open **Intune admin center**.
2. Go to **Devices** > **Scripts and remediations** > **Remediations**.
3. Select **Create script package**.
4. Name:
   - `MK-Defender-KEV-Version-Compliance`
5. Upload:
   - Detection script: `Detect-DefenderKevVersionCompliance.ps1`
   - Remediation script: `Remediate-DefenderKevVersionCompliance.ps1`
6. Settings:
   - **Run this script using the logged-on credentials:** No.
   - **Enforce script signature check:** No, unless scripts are signed.
   - **Run script in 64-bit PowerShell:** Yes.
7. Schedule:
   - Start with every 1 day for pilot.
   - Increase to every 8 hours during active KEV response if needed.
8. Assignment:
   - Pilot group first.
   - Then all Windows endpoints.

## Part 3 - Validate

### In Intune

1. Go to **Devices** > **Scripts and remediations** > your remediation package.
2. Review:
   - Detection status.
   - Remediation status.
   - Failed devices.

### On a device

Check log:

```text
C:\MK-LogFiles\Detect-DefenderKevVersionCompliance.log
C:\MK-LogFiles\Remediate-DefenderKevVersionCompliance.log
```

Run locally:

```powershell
Get-MpComputerStatus | Select-Object AMEngineVersion, AMProductVersion, AntivirusSignatureVersion, AntivirusSignatureLastUpdated
```

Expected minimums:

```text
AMEngineVersion >= 1.1.26040.8
AMProductVersion >= 4.18.26040.7
```

## Part 4 - Rollback

Do not roll back Defender engine/platform/security intelligence versions unless Microsoft Support explicitly instructs it.

Safe rollback actions:

- Move remediation package from all devices back to pilot group.
- Change schedule to daily instead of every 8 hours.
- Disable only the remediation package, not Defender updates.
- Keep detection/reporting enabled.

## Part 5 - Follow-up automation

Create a daily report from Intune remediation output or Defender Advanced Hunting with:

- Device name.
- Last seen.
- Engine version.
- Platform version.
- Security intelligence version.
- Compliance state.
- Remediation result.
