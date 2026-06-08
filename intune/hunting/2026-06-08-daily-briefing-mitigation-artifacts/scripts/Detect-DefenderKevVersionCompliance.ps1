# ============================================================================
# Eriteach Scripts
# Author: Robel (https://github.com/Thugney)
# Repository: https://github.com/Thugney/eriteach-scripts
# License: MIT
# ============================================================================

<#
.SYNOPSIS
    Kontrollerer Defender motor- og plattformversjon mot kjente KEV-minimum.

.DESCRIPTION
    Intune Proactive Remediation detection script for Microsoft Defender KEV
    mitigation. The script checks Microsoft Defender Malware Protection Engine
    and Antimalware Platform versions using Get-MpComputerStatus. It exits 0
    when the endpoint is compliant and exits 1 when remediation is required.

.NOTES
    Author: Eriteach
    Version: 1.0
    Intune Run Context: System
#>

$LogRoot = 'C:\MK-LogFiles'
$LogPath = Join-Path -Path $LogRoot -ChildPath 'Detect-DefenderKevVersionCompliance.log'
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

try {
    Write-Log -Message 'Starting Defender KEV version compliance detection.'

    $Status = Get-MpComputerStatus -ErrorAction Stop
    $EngineVersion = [version]$Status.AMEngineVersion
    $PlatformVersion = [version]$Status.AMProductVersion

    Write-Log -Message ('AMEngineVersion={0}; AMProductVersion={1}; AntivirusSignatureVersion={2}; AntivirusSignatureLastUpdated={3}' -f $Status.AMEngineVersion, $Status.AMProductVersion, $Status.AntivirusSignatureVersion, $Status.AntivirusSignatureLastUpdated)

    $EngineCompliant = $EngineVersion -ge $MinimumEngineVersion
    $PlatformCompliant = $PlatformVersion -ge $MinimumPlatformVersion

    if ($EngineCompliant -and $PlatformCompliant) {
        Write-Log -Message 'Device is compliant with Defender KEV minimum versions.'
        exit 0
    }

    if (-not $EngineCompliant) {
        Write-Log -Message ('Defender engine is below minimum. Current={0}; Required={1}' -f $EngineVersion, $MinimumEngineVersion) -Level WARNING
    }

    if (-not $PlatformCompliant) {
        Write-Log -Message ('Defender platform is below minimum. Current={0}; Required={1}' -f $PlatformVersion, $MinimumPlatformVersion) -Level WARNING
    }

    exit 1
}
catch {
    Write-Log -Message ('Detection failed: {0}' -f $_.Exception.Message) -Level ERROR
    exit 1
}
