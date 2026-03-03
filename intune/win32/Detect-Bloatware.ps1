<#
.SYNOPSIS
    Detects if bloatware is present on the device.

.DESCRIPTION
    Win32 App Detection Script for Intune.
    Checks for key bloatware apps and registry settings.

    Exit Codes:
    - Exit 0 = Bloatware NOT found (compliant - app "installed")
    - Exit 1 = Bloatware FOUND (non-compliant - needs remediation)

.NOTES
    Author: robwol
    Version: 2.0
    Deployment: Win32 App Detection Script
    Context: System

    IMPORTANT: This list must match Remove-Bloatware.ps1 and Config-AppList.ps1
#>


# KEY APPS FOR DETECTION (Subset for fast check)
# If ANY of these exist, device needs remediation
# Must match Config-AppList.ps1

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
    # NOTE: These apps are checked but some may be protected and cannot be removed
    # Detection only includes apps that CAN actually be removed
)


# DETECTION LOGIC


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


# EXIT

if ($bloatwareFound) {
    # Bloatware exists - remediation needed
    # Win32 detection: Exit 1 = "Not Installed" = Run install/remediation
    exit 1
}
else {
    # System is clean
    Write-Output "System is clean - no bloatware detected"
    # Win32 detection: Exit 0 = "Installed" = No action needed
    exit 0
}
