# ============================================================================
# Eriteach Scripts
# Author: Robel (https://github.com/Thugney)
# Repository: https://github.com/Thugney/eriteach-scripts
# License: MIT
# ============================================================================

<#
.SYNOPSIS
    Detection script — checks M365 Apps channel and blocking registry keys

.DESCRIPTION
    Checks if Microsoft 365 Apps (Click-to-Run) is configured for Monthly Enterprise Channel.
    Also detects blocking GPO-based registry keys that prevent Cloud Update (config.office.com)
    from managing the update channel.

    Exit 0 = Compliant (Monthly Enterprise Channel, no blocking registry keys)
    Exit 1 = Non-compliant (wrong channel or blocking registry keys present)

.NOTES
    Author: Eriteach
    Version: 1.1
    Intune Run Context: System
    Schedule: Daily
    Assignment: All Devices (Windows 10/11 filter)
#>

$logPath = "C:\MK-LogFiles\M365Apps-ChannelSwitch-Detect.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$timestamp [$Level] $Message"
    $logDir = Split-Path -Path $logPath -Parent
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
    $logEntry | Out-File -FilePath $logPath -Append -Encoding UTF8
    Write-Host $logEntry
}

# Monthly Enterprise Channel CDNBaseUrl
$targetCDNBaseUrl = "http://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6"
$c2rRegPath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
$policiesRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate"

try {
    Write-Log "Detection started" -Level INFO

    # Check if Click-to-Run is installed
    if (-not (Test-Path $c2rRegPath)) {
        Write-Log "Click-to-Run registry key not found. M365 Apps not installed." -Level WARNING
        Write-Log "Skipping — no action needed" -Level INFO
        exit 0
    }

    $nonCompliant = $false
    $issues = @()

    # Check current CDNBaseUrl (effective channel)
    $currentCDN = (Get-ItemProperty -Path $c2rRegPath -Name "CDNBaseUrl" -ErrorAction SilentlyContinue).CDNBaseUrl
    Write-Log "Current CDNBaseUrl: $currentCDN" -Level INFO

    if ($currentCDN -ne $targetCDNBaseUrl) {
        $nonCompliant = $true
        $issues += "CDNBaseUrl is not Monthly Enterprise Channel"
        Write-Log "CDNBaseUrl is NOT Monthly Enterprise Channel" -Level WARNING
    } else {
        Write-Log "CDNBaseUrl is correct — Monthly Enterprise Channel" -Level INFO
    }

    # Check UpdateChannel under Configuration
    $updateChannel = (Get-ItemProperty -Path $c2rRegPath -Name "UpdateChannel" -ErrorAction SilentlyContinue).UpdateChannel
    if ($updateChannel -and $updateChannel -ne $targetCDNBaseUrl) {
        $nonCompliant = $true
        $issues += "UpdateChannel points to wrong channel: $updateChannel"
        Write-Log "UpdateChannel under Configuration is wrong: $updateChannel" -Level WARNING
    }

    # Check for blocking GPO/Intune Admin Template registry keys
    $blockingKeys = @("updatebranch", "updatepath", "updatetargetversion")

    if (Test-Path $policiesRegPath) {
        foreach ($key in $blockingKeys) {
            $value = (Get-ItemProperty -Path $policiesRegPath -Name $key -ErrorAction SilentlyContinue).$key
            if ($null -ne $value -and $value -ne "") {
                $nonCompliant = $true
                $issues += "Blocking registry key found: $key = $value"
                Write-Log "Blocking policy key found: $key = $value" -Level WARNING
            }
        }
    } else {
        Write-Log "No Office Update policy keys found (good — Cloud Update can manage)" -Level INFO
    }

    if ($nonCompliant) {
        Write-Log "Device is NOT compliant. Issues: $($issues -join '; ')" -Level WARNING
        exit 1
    } else {
        Write-Log "Device is compliant — Monthly Enterprise Channel, no blocking keys" -Level INFO
        exit 0
    }

} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
