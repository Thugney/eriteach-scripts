# Eriteach Scripts

PowerShell scripts for Intune, Autopilot, and Microsoft 365 management.

## Structure

```
intune/
  remediations/     # Proactive remediation scripts (detection + remediation pairs)
  win32/            # Win32 app scripts (detection + install pairs)
deployment/         # OS deployment and imaging scripts
```

## Usage

Scripts are referenced from [blog.eriteach.com](https://blog.eriteach.com). Each script includes a header with:

- `.SYNOPSIS` - What it does
- `.DESCRIPTION` - How it works
- `.NOTES` - Author, version, Intune run context

## Scripts

### Intune Remediations

| Script | Purpose |
|--------|---------|
| `firefox-update-detection.ps1` | Detects if Firefox needs updating |
| `firefox-update-remediation.ps1` | Downloads and installs latest Firefox |
| `firefox-removal-detection.ps1` | Detects Firefox installations (registry, Program Files, user profiles) |
| `firefox-removal-remediation.ps1` | Removes Firefox completely (uninstall, files, shortcuts, services, tasks) |
| `primaryuser-restriction-detection.ps1` | Detects if login is restricted to Intune primary user |
| `primaryuser-restriction-remediation.ps1` | Restricts login to only primary user + Administrators |
| `diskspace-detection.ps1` | Detects low disk space using dual thresholds (15GB and 10%) |
| `diskspace-remediation.ps1` | Silently cleans temp files, caches, logs, and recycle bin |
| `m365apps-channel-switch-detection.ps1` | Detects wrong M365 Apps update channel and blocking GPO registry keys |
| `m365apps-channel-switch-remediation.ps1` | Switches M365 Apps to Monthly Enterprise Channel and removes blocking keys |

### Intune Win32 Apps

| Script | Purpose |
|--------|---------|
| `Detect-Bloatware.ps1` | Win32 detection script - checks for bloatware apps and registry settings |
| `Remove-Bloatware.ps1` | Win32 install script - removes 119+ bloatware apps and applies registry hardening |

### Deployment

| Script | Purpose |
|--------|---------|
| `inject-wifi-drivers.ps1` | Injects HP WiFi drivers into Windows 11 install.wim for offline deployment |
| `Build-ISO.ps1` | Creates debloated Windows 11 ISOs with HP WiFi drivers, registry tweaks, and OOBE skip for Autopilot |
