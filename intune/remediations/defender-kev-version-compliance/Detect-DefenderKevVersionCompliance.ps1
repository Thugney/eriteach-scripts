# ============================================================================
# Eriteach Scripts
# Author: Robel (https://github.com/Thugney)
# Repository: https://github.com/Thugney/eriteach-scripts
# License: MIT
# ============================================================================

<#
.SYNOPSIS
    Kontrollerer Microsoft Defender motor- og plattformversjon.

.DESCRIPTION
    Intune Proactive Remediation detection script for Microsoft Defender
    Antivirus version compliance. The script checks Microsoft Defender
    Malware Protection Engine and Antimalware Platform versions using
    Get-MpComputerStatus.

    Exit 0 = compliant.
    Exit 1 = remediation required or detection failed.

    Update the minimum versions before use. They should come from the
    Microsoft advisory or rollout requirement you are responding to.

.NOTES
    Author: Eriteach
    Version: 1.0
    Intune Run Context: System
    Run using logged-on credentials: No
#>

$LogRoot = 'C:\MK-LogFiles'
$LogPath = Join-Path -Path $LogRoot -ChildPath 'Detect-DefenderKevVersionCompliance.log'

# Example minimums. Replace with the required Microsoft Defender versions for your rollout.
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
    Write-Log -Message 'Starting Defender version compliance detection.'

    $Status = Get-MpComputerStatus -ErrorAction Stop
    $EngineVersion = [version]$Status.AMEngineVersion
    $PlatformVersion = [version]$Status.AMProductVersion

    Write-Log -Message ('AMEngineVersion={0}; AMProductVersion={1}; AntivirusSignatureVersion={2}; AntivirusSignatureLastUpdated={3}' -f $Status.AMEngineVersion, $Status.AMProductVersion, $Status.AntivirusSignatureVersion, $Status.AntivirusSignatureLastUpdated)

    $EngineCompliant = $EngineVersion -ge $MinimumEngineVersion
    $PlatformCompliant = $PlatformVersion -ge $MinimumPlatformVersion

    if ($EngineCompliant -and $PlatformCompliant) {
        Write-Log -Message 'Device is compliant with the configured Defender minimum versions.'
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
