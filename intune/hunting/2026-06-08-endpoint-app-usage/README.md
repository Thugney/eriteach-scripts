# Endpoint app usage inventory - 2026-06-08

Purpose: export applications that are installed and/or actually used by endpoint clients.

## Files

- `Export-TenantEndpointAppUsage.ps1` - interactive PowerShell export to Excel.
- `tenant-endpoint-app-usage.kql` - standalone Defender Advanced Hunting query.

## Recommended first use

1. Open Microsoft Defender XDR.
2. Go to **Hunting** > **Advanced hunting**.
3. Paste and run `tenant-endpoint-app-usage.kql`.
4. Confirm the app names/device counts look sane.
5. From an admin workstation, run the PowerShell script:

```powershell
.\Export-TenantEndpointAppUsage.ps1 -IncludeIntuneDetectedApps
```

Default output:

```text
C:\MK-LogFiles\EndpointAppUsage_<timestamp>.xlsx
```

## Recommended lookback

Default is **45 days**. Use:

- `30` days for strict current usage.
- `45` days for normal control baseline.
- `90` days before cleanup/removal decisions.

## Required access

Interactive Graph delegated scopes:

- `SecurityEvents.Read.All`
- `DeviceManagementManagedDevices.Read.All` when using `-IncludeIntuneDetectedApps`

Typical roles:

- Security Reader or Global Reader for Advanced Hunting
- Intune Reader for Intune detected apps

## Workbook sheets

- `Summary`
- `ControlView`
- `DefenderInUse`
- `DefenderInstalled`
- `IntuneDetected` when requested
