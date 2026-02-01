# Eriteach Scripts

PowerShell scripts for Intune, Autopilot, and Microsoft 365 management.

## Structure

```
intune/
  remediations/     # Proactive remediation scripts (detection + remediation pairs)
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
| `primaryuser-restriction-detection.ps1` | Detects if login is restricted to Intune primary user |
| `primaryuser-restriction-remediation.ps1` | Restricts login to only primary user + Administrators |
