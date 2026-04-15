# ============================================================================
# Eriteach Scripts
# Author: Robel (https://github.com/Thugney)
# Repository: https://github.com/Thugney/eriteach-scripts
# License: MIT
# ============================================================================

<#
.SYNOPSIS
    Remediation script — switches M365 Apps to Monthly Enterprise Channel

.DESCRIPTION
    Performs the following remediation actions:
    1. Removes blocking GPO/Admin Template registry keys under Policies\Microsoft\office
       that prevent Cloud Update (config.office.com) from managing the update channel
    2. Sets CDNBaseUrl to Monthly Enterprise Channel
    3. Sets UpdateChannel to Monthly Enterprise Channel
    4. Triggers an Office update check to accelerate the channel switch
    5. Verifies the changes were applied

    Exit 0 = Remediation successful
    Exit 1 = Remediation failed

.NOTES
    Author: Eriteach
    Version: 1.1
    Intune Run Context: System
    Assignment: All Devices (Windows 10/11 filter)
#>

$logPath = "C:\MK-LogFiles\M365Apps-ChannelSwitch-Remediate.log"

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
    Write-Log "Remediation started" -Level INFO

    # Check if Click-to-Run is installed
    if (-not (Test-Path $c2rRegPath)) {
        Write-Log "Click-to-Run not found. M365 Apps not installed. Skipping." -Level WARNING
        exit 0
    }

    # ============================================================
    # Step 1: Remove blocking policy registry keys
    # ============================================================
    Write-Log "Step 1: Removing blocking policy keys" -Level INFO

    $blockingKeys = @("updatebranch", "updatepath", "updatetargetversion")

    if (Test-Path $policiesRegPath) {
        foreach ($key in $blockingKeys) {
            $value = (Get-ItemProperty -Path $policiesRegPath -Name $key -ErrorAction SilentlyContinue).$key
            if ($null -ne $value) {
                Remove-ItemProperty -Path $policiesRegPath -Name $key -Force -ErrorAction Stop
                Write-Log "Removed blocking key: $key (old value: $value)" -Level INFO
            }
        }

        # Also remove enableautomaticupdates and updatedeadline if set by Admin Template
        $additionalKeys = @("enableautomaticupdates", "updatedeadline")
        foreach ($key in $additionalKeys) {
            $value = (Get-ItemProperty -Path $policiesRegPath -Name $key -ErrorAction SilentlyContinue).$key
            if ($null -ne $value) {
                Remove-ItemProperty -Path $policiesRegPath -Name $key -Force -ErrorAction Stop
                Write-Log "Removed policy key: $key (old value: $value)" -Level INFO
            }
        }

        # Check if the policies key is now empty and clean up
        $remainingValues = Get-ItemProperty -Path $policiesRegPath -ErrorAction SilentlyContinue
        $propertyCount = ($remainingValues.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }).Count
        if ($propertyCount -eq 0) {
            Remove-Item -Path $policiesRegPath -Force -ErrorAction SilentlyContinue
            Write-Log "Removed empty policy key: $policiesRegPath" -Level INFO
        }
    } else {
        Write-Log "No policy keys found — no cleanup needed" -Level INFO
    }

    # ============================================================
    # Step 2: Set CDNBaseUrl to Monthly Enterprise Channel
    # ============================================================
    Write-Log "Step 2: Setting CDNBaseUrl to Monthly Enterprise Channel" -Level INFO

    $currentCDN = (Get-ItemProperty -Path $c2rRegPath -Name "CDNBaseUrl" -ErrorAction SilentlyContinue).CDNBaseUrl
    Write-Log "Current CDNBaseUrl: $currentCDN" -Level INFO

    if ($currentCDN -ne $targetCDNBaseUrl) {
        Set-ItemProperty -Path $c2rRegPath -Name "CDNBaseUrl" -Value $targetCDNBaseUrl -Force -ErrorAction Stop
        Write-Log "CDNBaseUrl updated to Monthly Enterprise Channel" -Level INFO
    } else {
        Write-Log "CDNBaseUrl is already correct" -Level INFO
    }

    # ============================================================
    # Step 3: Set UpdateChannel to match
    # ============================================================
    Write-Log "Step 3: Setting UpdateChannel to Monthly Enterprise Channel" -Level INFO

    Set-ItemProperty -Path $c2rRegPath -Name "UpdateChannel" -Value $targetCDNBaseUrl -Force -ErrorAction Stop
    Write-Log "UpdateChannel updated to Monthly Enterprise Channel" -Level INFO

    # ============================================================
    # Step 4: Trigger Office update check
    # ============================================================
    Write-Log "Step 4: Triggering Office update check" -Level INFO

    $c2rExe = Join-Path $env:CommonProgramFiles "Microsoft Shared\ClickToRun\OfficeC2RClient.exe"

    if (Test-Path $c2rExe) {
        Start-Process -FilePath $c2rExe -ArgumentList "/update user displaylevel=false forceappshutdown=false" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        Write-Log "Office update check triggered via OfficeC2RClient.exe" -Level INFO
    } else {
        Write-Log "OfficeC2RClient.exe not found at expected path: $c2rExe" -Level WARNING
    }

    # ============================================================
    # Step 5: Verify remediation
    # ============================================================
    Write-Log "Step 5: Verifying remediation" -Level INFO

    $verifiedCDN = (Get-ItemProperty -Path $c2rRegPath -Name "CDNBaseUrl" -ErrorAction SilentlyContinue).CDNBaseUrl
    $verifiedChannel = (Get-ItemProperty -Path $c2rRegPath -Name "UpdateChannel" -ErrorAction SilentlyContinue).UpdateChannel

    if ($verifiedCDN -eq $targetCDNBaseUrl -and $verifiedChannel -eq $targetCDNBaseUrl) {
        Write-Log "Verified — CDNBaseUrl and UpdateChannel are Monthly Enterprise Channel" -Level INFO
    } else {
        Write-Log "Verification partial — CDNBaseUrl: $verifiedCDN, UpdateChannel: $verifiedChannel" -Level WARNING
    }

    # Check no blocking keys remain
    if (Test-Path $policiesRegPath) {
        $remainingBlockers = $blockingKeys | Where-Object {
            $null -ne (Get-ItemProperty -Path $policiesRegPath -Name $_ -ErrorAction SilentlyContinue).$_
        }
        if ($remainingBlockers.Count -gt 0) {
            Write-Log "WARNING: Blocking keys still present: $($remainingBlockers -join ', ')" -Level WARNING
            Write-Log "Intune Admin Template may be writing these back. Remove the policy from Intune first!" -Level WARNING
        }
    }

    Write-Log "Remediation complete" -Level INFO
    exit 0

} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
