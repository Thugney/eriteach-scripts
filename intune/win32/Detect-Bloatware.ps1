# ============================================================================
# Eriteach Scripts
# Author: Robel (https://github.com/Thugney)
# Repository: https://github.com/Thugney/eriteach-scripts
# License: MIT
# ============================================================================

<#
.SYNOPSIS
Detects if bloatware is present on the device.

.DESCRIPTION
Win32 App Detection Script for Intune. Checks for key bloatware apps
and registry settings. Returns exit 0 if clean (app "installed"),
exit 1 if bloatware found (needs remediation).

.NOTES
Author: Eriteach
Version: 2.0
Intune Run Context: System
#>

# Key apps for detection (subset for fast check)
$KeyAppsForDetection = @(
    "Microsoft.BingNews"
    "Microsoft.BingWeather"
    "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.ZuneVideo"
    "Clipchamp.Clipchamp"
    "Microsoft.Copilot"
    "MicrosoftTeams"                         # Personal Teams
    "Microsoft.GamingApp"
    "Microsoft.XboxApp"
    "king.com.CandyCrushSaga"
)

$bloatwareFound = $false

# Check for bloatware apps
foreach ($app in $KeyAppsForDetection) {
    $package = Get-AppxPackage -Name "*$app*" -AllUsers -ErrorAction SilentlyContinue
    if ($package) {
        $bloatwareFound = $true
        break
    }
}

# Check Widgets registry (should be disabled)
if (-not $bloatwareFound) {
    $widgetsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (-not (Test-Path $widgetsPath)) {
        $bloatwareFound = $true
    }
    else {
        $widgetsValue = (Get-ItemProperty $widgetsPath -Name "AllowNewsAndInterests" -ErrorAction SilentlyContinue).AllowNewsAndInterests
        if ($widgetsValue -ne 0) {
            $bloatwareFound = $true
        }
    }
}

# Check Copilot registry (should be disabled)
if (-not $bloatwareFound) {
    $copilotPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
    if (-not (Test-Path $copilotPath)) {
        $bloatwareFound = $true
    }
    else {
        $copilotValue = (Get-ItemProperty $copilotPath -Name "TurnOffWindowsCopilot" -ErrorAction SilentlyContinue).TurnOffWindowsCopilot
        if ($copilotValue -ne 1) {
            $bloatwareFound = $true
        }
    }
}

# Check Consumer Features registry (should be disabled)
if (-not $bloatwareFound) {
    $consumerPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $consumerPath)) {
        $bloatwareFound = $true
    }
    else {
        $consumerValue = (Get-ItemProperty $consumerPath -Name "DisableWindowsConsumerFeatures" -ErrorAction SilentlyContinue).DisableWindowsConsumerFeatures
        if ($consumerValue -ne 1) {
            $bloatwareFound = $true
        }
    }
}

# Exit codes
if ($bloatwareFound) {
    exit 1  # Not installed = needs remediation
}
else {
    Write-Output "System is clean - no bloatware detected"
    exit 0  # Installed = compliant
}
