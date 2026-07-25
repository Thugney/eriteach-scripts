# ============================================================================
# Eriteach Scripts
# Repository: https://github.com/Thugney/eriteach-scripts
# License: MIT
# ============================================================================

<#
.SYNOPSIS
    Reparer Windows Update-klienthelse trygt for Microsoft Intune Remediations.
.DESCRIPTION
    Conservative Windows Update health remediation for Microsoft Intune. The default
    repair level starts required services, corrects disabled service start modes,
    removes stale BITS queue files, ensures SoftwareDistribution exists, and optionally
    triggers a Windows Update scan. It does not delete policy registry keys, change
    telemetry policy, reset service security descriptors, re-register DLLs, download
    external binaries, or restart the device.

    Cache reset is available only when RepairLevel is explicitly set to CacheReset.
    PolicyUnlock is intentionally not implemented because Intune/GPO policy ownership
    must be changed in policy, not by endpoint-side registry deletion.
.NOTES
    Version: 1.0.0
    Intune Run Context: System
    Run in 64-bit PowerShell: Yes
    Log: C:\MK-LogFiles\Remediate-WindowsUpdateHealth.log
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [ValidateSet('Conservative','CacheReset')]
    [string]$RepairLevel = 'Conservative',

    [Parameter()]
    [switch]$TriggerScan,

    [Parameter()]
    [switch]$DryRun
)

$ScriptName = 'Remediate-WindowsUpdateHealth'
$LogDirectory = 'C:\MK-LogFiles'
$LogPath = Join-Path -Path $LogDirectory -ChildPath "$ScriptName.log"

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    try {
        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }
        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "$Timestamp [$Level] $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
    }
    catch {
        Write-Output "Logging failed: $($_.Exception.Message)"
    }
}

function Invoke-SafeAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    try {
        if ($DryRun) {
            Write-Log -Message "DRY-RUN: $Description"
            return $true
        }

        Write-Log -Message $Description
        & $Action
        return $true
    }
    catch {
        Write-Log -Level 'ERROR' -Message "$Description failed: $($_.Exception.Message)"
        return $false
    }
}

function Set-ServiceHealth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Automatic','Manual')]
        [string]$StartupType
    )

    $Service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
    if ($null -eq $Service) {
        Write-Log -Level 'WARN' -Message "Service not found: $Name"
        return $false
    }

    if ($Service.StartMode -eq 'Disabled') {
        $Result = Invoke-SafeAction -Description "Set $Name startup type to $StartupType" -Action { Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop }
        if (-not $Result) { return $false }
    }

    $CurrentService = Get-Service -Name $Name -ErrorAction Stop
    if ($CurrentService.Status -ne 'Running') {
        return Invoke-SafeAction -Description "Start service $Name" -Action { Start-Service -Name $Name -ErrorAction Stop }
    }

    Write-Log -Message "Service healthy: $Name"
    return $true
}

function Clear-StaleBitsQueue {
    $QmgrPath = Join-Path -Path $env:ALLUSERSPROFILE -ChildPath 'Microsoft\Network\Downloader'
    if (-not (Test-Path -LiteralPath $QmgrPath)) {
        Write-Log -Message "BITS queue folder not found: $QmgrPath"
        return $true
    }

    $Files = Get-ChildItem -Path $QmgrPath -Filter 'qmgr*.dat' -ErrorAction SilentlyContinue
    if ($Files.Count -eq 0) {
        Write-Log -Message 'No BITS queue files found.'
        return $true
    }

    $Stopped = Invoke-SafeAction -Description 'Stop BITS before stale queue cleanup' -Action { Stop-Service -Name 'BITS' -Force -ErrorAction Stop }
    if (-not $Stopped) { return $false }

    foreach ($File in $Files) {
        Invoke-SafeAction -Description "Remove BITS queue file $($File.FullName)" -Action { Remove-Item -LiteralPath $File.FullName -Force -ErrorAction Stop } | Out-Null
    }

    return Invoke-SafeAction -Description 'Start BITS after stale queue cleanup' -Action { Start-Service -Name 'BITS' -ErrorAction Stop }
}

function Reset-WindowsUpdateCache {
    $ServiceNames = @('wuauserv', 'BITS', 'cryptsvc')
    foreach ($ServiceName in $ServiceNames) {
        Invoke-SafeAction -Description "Stop service $ServiceName for cache reset" -Action { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue } | Out-Null
    }

    $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $SoftwareDistribution = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution'
    $Catroot2 = Join-Path -Path $env:SystemRoot -ChildPath 'System32\Catroot2'

    foreach ($Path in @($SoftwareDistribution, $Catroot2)) {
        if (Test-Path -LiteralPath $Path) {
            $BackupPath = "$Path.bak-$Stamp"
            Invoke-SafeAction -Description "Rename $Path to $BackupPath" -Action { Rename-Item -LiteralPath $Path -NewName (Split-Path -Path $BackupPath -Leaf) -Force -ErrorAction Stop } | Out-Null
        }
    }

    foreach ($ServiceName in $ServiceNames) {
        Invoke-SafeAction -Description "Start service $ServiceName after cache reset" -Action { Start-Service -Name $ServiceName -ErrorAction SilentlyContinue } | Out-Null
    }
}

function Start-UpdateScanSafe {
    $UsoClient = Join-Path -Path $env:SystemRoot -ChildPath 'System32\UsoClient.exe'
    if (Test-Path -LiteralPath $UsoClient) {
        return Invoke-SafeAction -Description 'Trigger Windows Update scan with UsoClient StartScan' -Action { Start-Process -FilePath $UsoClient -ArgumentList 'StartScan' -WindowStyle Hidden -ErrorAction Stop }
    }

    $Wuauclt = Join-Path -Path $env:SystemRoot -ChildPath 'System32\wuauclt.exe'
    if (Test-Path -LiteralPath $Wuauclt) {
        return Invoke-SafeAction -Description 'Trigger Windows Update detection with wuauclt /detectnow' -Action { Start-Process -FilePath $Wuauclt -ArgumentList '/detectnow' -WindowStyle Hidden -ErrorAction Stop }
    }

    Write-Log -Level 'WARN' -Message 'No supported scan trigger executable found.'
    return $false
}

try {
    Write-Log -Message "=== Windows Update remediation started. RepairLevel=$RepairLevel DryRun=$DryRun TriggerScan=$TriggerScan ==="
    $FailureCount = 0

    $ServicePlan = @(
        @{ Name = 'wuauserv'; StartupType = 'Manual' },
        @{ Name = 'BITS'; StartupType = 'Manual' },
        @{ Name = 'cryptsvc'; StartupType = 'Automatic' }
    )

    foreach ($Item in $ServicePlan) {
        if (-not (Set-ServiceHealth -Name $Item.Name -StartupType $Item.StartupType)) { $FailureCount++ }
    }

    if (-not (Clear-StaleBitsQueue)) { $FailureCount++ }

    $SoftwareDistribution = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution'
    if (-not (Test-Path -LiteralPath $SoftwareDistribution)) {
        if (-not (Invoke-SafeAction -Description "Create missing folder $SoftwareDistribution" -Action { New-Item -Path $SoftwareDistribution -ItemType Directory -Force -ErrorAction Stop | Out-Null })) { $FailureCount++ }
    }

    if ($RepairLevel -eq 'CacheReset') {
        Write-Log -Level 'WARN' -Message 'CacheReset selected. Cache folders will be renamed, not deleted.'
        Reset-WindowsUpdateCache
    }

    if ($TriggerScan) {
        if (-not (Start-UpdateScanSafe)) { $FailureCount++ }
    }

    if ($FailureCount -gt 0) {
        Write-Output "Completed with $FailureCount failure(s). See $LogPath"
        Write-Log -Level 'ERROR' -Message "Remediation completed with $FailureCount failure(s)."
        exit 1
    }

    Write-Output "Windows Update health remediation completed. See $LogPath"
    Write-Log -Message 'Remediation completed successfully.'
    exit 0
}
catch {
    Write-Log -Level 'ERROR' -Message "Remediation failed: $($_.Exception.Message)"
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
