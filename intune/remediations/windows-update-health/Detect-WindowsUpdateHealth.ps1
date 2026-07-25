# ============================================================================
# Eriteach Scripts
# Repository: https://github.com/Thugney/eriteach-scripts
# License: MIT
# ============================================================================

<#
.SYNOPSIS
    Oppdager Windows Update-klienthelse for Microsoft Intune Remediations.
.DESCRIPTION
    Detection script for Microsoft Intune Remediations. It performs read-only checks for
    Windows Update client health signals that are safe to evaluate at scale:
    required services, disabled service start modes, paused update state, BITS queue
    residue, Windows Update cache availability, recent hotfix signal, and pending reboot.

    The script does not modify policy, services, cache folders, or registry values.
    Exit 0 means no remediation is required. Exit 1 means the paired remediation script
    should run. Exit 1 is limited to conditions the conservative remediation can address.
.NOTES
    Version: 1.0.0
    Intune Run Context: System
    Run in 64-bit PowerShell: Yes
    Log: C:\MK-LogFiles\Detect-WindowsUpdateHealth.log
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$MaxQmgrFileAgeDays = 7,

    [Parameter()]
    [int]$MaxLastHotfixAgeDays = 45
)

$ScriptName = 'Detect-WindowsUpdateHealth'
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

function Get-RegistryValueSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        $Item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $Item.$Name
    }
    catch {
        return $null
    }
}

function Test-PendingReboot {
    $Paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    )

    foreach ($Path in $Paths) {
        try {
            if ($Path -like '*Session Manager') {
                $Value = Get-RegistryValueSafe -Path $Path -Name 'PendingFileRenameOperations'
                if ($null -ne $Value) { return $true }
            }
            elseif (Test-Path -LiteralPath $Path) {
                return $true
            }
        }
        catch {
            Write-Log -Level 'WARN' -Message "Pending reboot check failed for $Path : $($_.Exception.Message)"
        }
    }
    return $false
}

function Get-LatestHotfixAgeDays {
    try {
        $LatestHotfix = Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object -Property InstalledOn -Descending | Select-Object -First 1
        if ($null -eq $LatestHotfix) { return $null }
        return [int]((Get-Date) - [datetime]$LatestHotfix.InstalledOn).TotalDays
    }
    catch {
        Write-Log -Level 'WARN' -Message "Hotfix age check failed: $($_.Exception.Message)"
        return $null
    }
}

try {
    Write-Log -Message '=== Windows Update health detection started ==='
    $RemediationNeeded = $false
    $Findings = New-Object System.Collections.Generic.List[string]
    $Warnings = New-Object System.Collections.Generic.List[string]

    $ServiceNames = @('wuauserv', 'BITS', 'cryptsvc')
    foreach ($ServiceName in $ServiceNames) {
        try {
            $Service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
            if ($null -eq $Service) {
                $Findings.Add("Service missing: $ServiceName")
                $RemediationNeeded = $true
                continue
            }
            if ($Service.StartMode -eq 'Disabled') {
                $Findings.Add("Service disabled: $ServiceName")
                $RemediationNeeded = $true
            }
            if ($Service.State -ne 'Running') {
                $Findings.Add("Service not running: $ServiceName ($($Service.State))")
                $RemediationNeeded = $true
            }
        }
        catch {
            $Findings.Add("Service check failed: $ServiceName - $($_.Exception.Message)")
            $RemediationNeeded = $true
        }
    }

    $PausedQuality = Get-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings' -Name 'PausedQualityStatus'
    $PausedFeature = Get-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings' -Name 'PausedFeatureStatus'
    if ([string]$PausedQuality -eq '1') { $Warnings.Add('Quality updates appear paused. Verify Intune/GPO intent before changing policy.') }
    if ([string]$PausedFeature -eq '1') { $Warnings.Add('Feature updates appear paused. Verify Intune/GPO intent before changing policy.') }

    $QmgrPath = Join-Path -Path $env:ALLUSERSPROFILE -ChildPath 'Microsoft\Network\Downloader'
    if (Test-Path -LiteralPath $QmgrPath) {
        $OldQmgrFiles = Get-ChildItem -Path $QmgrPath -Filter 'qmgr*.dat' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$MaxQmgrFileAgeDays) }
        if ($OldQmgrFiles.Count -gt 0) {
            $Findings.Add("Old BITS queue files found: $($OldQmgrFiles.Count)")
            $RemediationNeeded = $true
        }
    }

    $SoftwareDistribution = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution'
    if (-not (Test-Path -LiteralPath $SoftwareDistribution)) {
        $Findings.Add('SoftwareDistribution folder is missing')
        $RemediationNeeded = $true
    }

    if (Test-PendingReboot) {
        $Warnings.Add('Pending reboot detected. Remediation will not force restart.')
    }

    $HotfixAgeDays = Get-LatestHotfixAgeDays
    if ($null -eq $HotfixAgeDays) {
        $Warnings.Add('Could not determine latest hotfix age.')
    }
    elseif ($HotfixAgeDays -gt $MaxLastHotfixAgeDays) {
        $Warnings.Add("Latest hotfix appears older than $MaxLastHotfixAgeDays days ($HotfixAgeDays days). Use Intune update rings/expedited updates for patch compliance.")
    }

    foreach ($Finding in $Findings) { Write-Log -Level 'WARN' -Message $Finding }
    foreach ($Warning in $Warnings) { Write-Log -Level 'WARN' -Message $Warning }

    if ($RemediationNeeded) {
        Write-Output "Non-Compliant: $($Findings -join '; ')"
        Write-Log -Level 'WARN' -Message 'Detection completed: remediation required.'
        exit 1
    }

    $WarningText = if ($Warnings.Count -gt 0) { " Warnings: $($Warnings -join '; ')" } else { '' }
    Write-Output "Compliant: Windows Update client health checks passed.$WarningText"
    Write-Log -Message 'Detection completed: compliant.'
    exit 0
}
catch {
    Write-Log -Level 'ERROR' -Message "Detection failed: $($_.Exception.Message)"
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
