# Defender KEV version compliance remediation

Intune Proactive Remediation pair for checking Microsoft Defender Antivirus engine/platform versions and triggering update mechanisms when an endpoint falls below a configured minimum.

## Files

- `Detect-DefenderKevVersionCompliance.ps1` - exits `1` when engine or platform versions are below configured minimums.
- `Remediate-DefenderKevVersionCompliance.ps1` - runs Defender update mechanisms and logs before/after versions.

## Intended use

Use this when a security advisory, known exploited vulnerability response, or internal baseline requires a specific Microsoft Defender engine/platform minimum.

The script does **not** decide the minimum versions for you. Update these variables before deployment:

```powershell
$MinimumEngineVersion = [version]'1.1.26040.8'
$MinimumPlatformVersion = [version]'4.18.26040.7'
```

## Intune settings

Recommended settings:

- Run this script using the logged-on credentials: **No**
- Enforce script signature check: according to your signing model
- Run script in 64-bit PowerShell: **Yes**
- Assignment: pilot first, then staged rollout

## Safety notes

- Detection is read-only.
- Remediation only triggers Microsoft Defender update mechanisms.
- Both scripts log to `C:\MK-LogFiles`.
- Use a pilot assignment first and validate Intune remediation output before broad rollout.

## Related docs

- Microsoft Intune remediations: https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/remediations
- Get-MpComputerStatus: https://learn.microsoft.com/en-us/powershell/module/defender/get-mpcomputerstatus
- Update-MpSignature: https://learn.microsoft.com/en-us/powershell/module/defender/update-mpsignature
