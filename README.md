# Eriteach Scripts

[![GitHub](https://img.shields.io/badge/GitHub-Thugney-181717?style=flat&logo=github)](https://github.com/Thugney)
[![Blog](https://img.shields.io/badge/Blog-eriteach.com-0d9488?style=flat&logo=hugo)](https://blog.eriteach.com)
[![YouTube](https://img.shields.io/badge/YouTube-Eriteach-FF0000?style=flat&logo=youtube)](https://www.youtube.com/@eriteach)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Eriteach-0A66C2?style=flat&logo=linkedin)](https://www.linkedin.com/in/eriteach/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

PowerShell scripts for **Intune**, **Autopilot**, and **Microsoft 365** management. Built for real-world enterprise environments.

## About

This repository contains a collection of scripts developed for Microsoft 365 and Intune administration. The focus is on automation, security hardening, and endpoint hygiene in production environments.

Detailed technical guides for these scripts can be found on [blog.eriteach.com](https://blog.eriteach.com).

## Structure

```
eriteach-scripts/
├── intune/
│   ├── remediations/     # Proactive remediation scripts (detection + remediation pairs)
│   └── win32/            # Win32 app scripts (detection + install pairs)
└── deployment/           # OS deployment and imaging scripts
```

## Scripts

### Intune Remediations (Proactive Remediations)

| Script | Purpose |
|--------|---------|
| [`zombie-apps-detection.ps1`](intune/remediations/zombie-apps-detection.ps1) | **NEW:** Detects unauthorized or EOL "zombie" software |
| [`zombie-apps-removal.ps1`](intune/remediations/zombie-apps-removal.ps1) | **NEW:** Silently uninstalls detected zombie apps |
| [`firefox-update-detection.ps1`](intune/remediations/firefox-update-detection.ps1) | Detects if Firefox needs updating |
| [`firefox-update-remediation.ps1`](intune/remediations/firefox-update-remediation.ps1) | Downloads and installs latest Firefox |
| [`firefox-removal-detection.ps1`](intune/remediations/firefox-removal-detection.ps1) | Detects Firefox installations |
| [`firefox-removal-remediation.ps1`](intune/remediations/firefox-removal-remediation.ps1) | Removes Firefox completely |
| [`primaryuser-restriction-detection.ps1`](intune/remediations/primaryuser-restriction-detection.ps1) | Detects if login is restricted to primary user |
| [`primaryuser-restriction-remediation.ps1`](intune/remediations/primaryuser-restriction-remediation.ps1) | Restricts login to primary user + Administrators |
| [`diskspace-detection.ps1`](intune/remediations/diskspace-detection.ps1) | Detects low disk space (15GB / 10% thresholds) |
| [`diskspace-remediation.ps1`](intune/remediations/diskspace-remediation.ps1) | Cleans temp files, caches, logs, recycle bin |
| [`m365apps-channel-switch-detection.ps1`](intune/remediations/m365apps-channel-switch-detection.ps1) | Detects wrong M365 Apps update channel |
| [`m365apps-channel-switch-remediation.ps1`](intune/remediations/m365apps-channel-switch-remediation.ps1) | Switches to Monthly Enterprise Channel |

### Intune Win32 Apps

| Script | Purpose |
|--------|---------|
| [`Detect-Bloatware.ps1`](intune/win32/Detect-Bloatware.ps1) | Win32 detection - checks for bloatware apps and registry settings |
| [`Remove-Bloatware.ps1`](intune/win32/Remove-Bloatware.ps1) | Win32 install - removes 119+ bloatware apps, applies registry hardening |

### Deployment

| Script | Purpose |
|--------|---------|
| [`Build-ISO.ps1`](deployment/Build-ISO.ps1) | Creates debloated Windows 11 ISOs with WiFi drivers and Autopilot-compatible OOBE |
| [`inject-wifi-drivers.ps1`](deployment/inject-wifi-drivers.ps1) | Injects HP WiFi drivers into Windows 11 install.wim |
| [`autounattend-education.xml`](deployment/autounattend-education.xml) | Autopilot-compatible autounattend for Windows 11 Education |
| [`autounattend-enterprise.xml`](deployment/autounattend-enterprise.xml) | Autopilot-compatible autounattend for Windows 11 Enterprise |

## Implementation Guide: Proactive Remediations

To use these scripts in Microsoft Intune:

1.  Navigate to **Devices** > **Scripts and remediations** > **Remediations**.
2.  Click **Create**.
3.  **Basics:** Provide a name (e.g., "Remediate - Zombie Software").
4.  **Settings:**
    *   **Detection script file:** Upload the `*-detection.ps1` script.
    *   **Remediation script file:** Upload the `*-remediation.ps1` (or `*-removal.ps1`) script.
    *   **Run this script using the logged-on credentials:** No.
    *   **Enforce script signature check:** No (unless you sign your scripts).
    *   **Run script in 64-bit PowerShell:** Yes.
5.  **Assignments:** Assign to a test group before a broad rollout.

## Usage (Script Header)

Each script includes a standard header for consistency:

```powershell
# ============================================================================
# Eriteach Scripts
# Author: Robel (https://github.com/Thugney)
# Repository: https://github.com/Thugney/eriteach-scripts
# License: MIT
# ============================================================================

<#
.SYNOPSIS
What it does.

.DESCRIPTION
How it works.

.NOTES
Author: Eriteach
Version: 1.1
Intune Run Context: System | User
#>
```

## Related

- [blog.eriteach.com](https://blog.eriteach.com) - Technical blog with detailed guides
- [YouTube: Eriteach](https://www.youtube.com/@eriteach) - Video tutorials (20,000+ subscribers)
- [TenantScope](https://github.com/Thugney/TenantScope) - M365 Tenant Toolkit for tenant management
- [Intune-AdmxToSettingsCatalog-Migrator](https://github.com/Thugney/Intune-AdmxToSettingsCatalog-Migrator) - Migrate ADMX-backed policies to Settings Catalog

## License

MIT License - see [LICENSE](LICENSE) for details.
