# ============================================================================
# Eriteach Scripts
# Author: Robel (https://github.com/Thugney)
# Repository: https://github.com/Thugney/eriteach-scripts
# License: MIT
# ============================================================================

<#
.SYNOPSIS
    Oppdaterer Defender signaturer og forsoker a trigge Defender plattformoppdatering.

.DESCRIPTION
    Intune Proactive Remediation remediation script for Microsoft Defender KEV
    mitigation. The script updates Defender security intelligence and triggers
    Microsoft Defender update mechanisms. It logs before and after versions so
    Intune remediation output can be used as evidence.

.NOTES
    Author: Eriteach
    Version: 1.0
    Intune Run Context: System
#>

$LogRoot = 'C:\MK-LogFiles'
$LogPath = Join-Path -Path $LogRoot -ChildPath 'Remediate-DefenderKevVersionCompliance.log'
$MinimumEngineVersion = [version]'1.1.26040.8'
$MinimumPlatformVersion = [version]'4.18.26040.7'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    try {
        if (-not (Test-Path -Path $LogRoot)) {
            New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
        }

        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $Entry = '{0} [{1}] {2}' -f $Timestamp, $Level, $Message
        $Entry | Out-File -FilePath $LogPath -Append -Encoding UTF8
        Write-Host $Entry
    }
    catch {
        Write-Host ('Logging failed: {0}' -f $_.Exception.Message)
    }
}

function Get-DefenderVersionState {
    $Status = Get-MpComputerStatus -ErrorAction Stop
    return [PSCustomObject]@{
        EngineVersion = [version]$Status.AMEngineVersion
        PlatformVersion = [version]$Status.AMProductVersion
        SignatureVersion = $Status.AntivirusSignatureVersion
        SignatureLastUpdated = $Status.AntivirusSignatureLastUpdated
    }
}

try {
    Write-Log -Message 'Starting Defender KEV remediation.'

    $Before = Get-DefenderVersionState
    Write-Log -Message ('Before: Engine={0}; Platform={1}; Signature={2}; SignatureLastUpdated={3}' -f $Before.EngineVersion, $Before.PlatformVersion, $Before.SignatureVersion, $Before.SignatureLastUpdated)

    try {
        Write-Log -Message 'Running Update-MpSignature.'
        Update-MpSignature -ErrorAction Stop
    }
    catch {
        Write-Log -Message ('Update-MpSignature failed: {0}' -f $_.Exception.Message) -Level WARNING
    }

    $MpCmdRun = Join-Path -Path $env:ProgramFiles -ChildPath 'Windows Defender\MpCmdRun.exe'
    if (Test-Path -Path $MpCmdRun) {
        try {
            Write-Log -Message 'Running MpCmdRun signature update.'
            Start-Process -FilePath $MpCmdRun -ArgumentList '-SignatureUpdate' -Wait -NoNewWindow -ErrorAction Stop
        }
        catch {
            Write-Log -Message ('MpCmdRun signature update failed: {0}' -f $_.Exception.Message) -Level WARNING
        }
    }
    else {
        Write-Log -Message ('MpCmdRun not found at {0}' -f $MpCmdRun) -Level WARNING
    }

    Start-Sleep -Seconds 20
    $After = Get-DefenderVersionState
    Write-Log -Message ('After: Engine={0}; Platform={1}; Signature={2}; SignatureLastUpdated={3}' -f $After.EngineVersion, $After.PlatformVersion, $After.SignatureVersion, $After.SignatureLastUpdated)

    if ($After.EngineVersion -ge $MinimumEngineVersion -and $After.PlatformVersion -ge $MinimumPlatformVersion) {
        Write-Log -Message 'Device is compliant after remediation.'
        exit 0
    }

    Write-Log -Message ('Device remains below minimum. Engine={0}/{1}; Platform={2}/{3}' -f $After.EngineVersion, $MinimumEngineVersion, $After.PlatformVersion, $MinimumPlatformVersion) -Level ERROR
    exit 1
}
catch {
    Write-Log -Message ('Remediation failed: {0}' -f $_.Exception.Message) -Level ERROR
    exit 1
}
