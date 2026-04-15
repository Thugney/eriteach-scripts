<#
.SYNOPSIS
    Remediation script for removing unauthorized or end-of-support software ("Zombie Software").

.DESCRIPTION
    Automatically uninstalls unauthorized or deprecated software detected by the companion script.
    Supports registry-based uninstalls (MSI, InnoSetup, NSIS) and file system cleanup.

.NOTES
    Author: eriteach
    Version: 1.1
    Intune Run Context: System
#>

$logPath = "C:\ProgramData\Eriteach\Logs\ZombieSoftware-Remediate.log"

#region Functions
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$timestamp [$Level] $Message"
    $logDir = Split-Path -Path $logPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    $logEntry | Out-File -FilePath $logPath -Append -Encoding UTF8
    Write-Host $logEntry
}

function Get-UninstallCommand {
    param([string]$RegistryKeyPath)
    $result = @{ Command = $null; Arguments = $null; Method = $null }
    $key = Get-ItemProperty -Path $RegistryKeyPath -ErrorAction SilentlyContinue
    if (-not $key) { return $result }

    $uninstallString = if ($key.QuietUninstallString) { $result.Method = "QuietUninstallString"; $key.QuietUninstallString }
                       elseif ($key.UninstallString) { $result.Method = "UninstallString"; $key.UninstallString }
                       else { return $result }

    if ($uninstallString -match '^"([^"]+)"\s*(.*)$') {
        $result.Command = $Matches[1]; $result.Arguments = $Matches[2]
    }
    elseif ($uninstallString -match '(?i)^msiexec(.*)$') {
        $result.Command = "msiexec.exe"
        $msiArgs = $Matches[1].Trim() -replace '(?i)/I', '/X'
        if ($msiArgs -notmatch '(?i)/q') { $msiArgs += " /qn /norestart" }
        $result.Arguments = $msiArgs
    }
    elseif ($uninstallString -match '^(\S+\.exe)\s*(.*)$') {
        $result.Command = $Matches[1]; $result.Arguments = $Matches[2]
    }
    else { $result.Command = $uninstallString }
    return $result
}

function Invoke-SilentUninstall {
    param([string]$RegistryKeyPath, [string]$TargetName)
    $uninstall = Get-UninstallCommand -RegistryKeyPath $RegistryKeyPath
    if (-not $uninstall.Command) { return $false }

    $command = $uninstall.Command
    $arguments = $uninstall.Arguments
    if ($uninstall.Method -eq "UninstallString") {
        if ($command -match '(?i)unins\d+\.exe' -or $RegistryKeyPath -match '_is1') {
            if ($arguments -notmatch '/SILENT|/VERYSILENT') { $arguments = "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES $arguments".Trim() }
        }
        elseif ($command -match '(?i)uninst.*\.exe') {
            if ($arguments -notmatch '/S') { $arguments = "/S $arguments".Trim() }
        }
    }

    try {
        $process = Start-Process -FilePath $command -ArgumentList $arguments -Wait -PassThru -NoNewWindow -ErrorAction Stop
        return ($process.ExitCode -eq 0 -or $process.ExitCode -eq 1641 -or $process.ExitCode -eq 3010)
    }
    catch { return $false }
}

function Remove-ApplicationFolder {
    param([string]$FolderPath)
    if (-not (Test-Path $FolderPath)) { return $true }
    try {
        $runningProcesses = Get-Process | Where-Object { $_.Path -and $_.Path -like "$FolderPath*" }
        foreach ($proc in $runningProcesses) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        Remove-Item -Path $FolderPath -Recurse -Force -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

function Resolve-RegistryPaths {
    param([string]$Path)
    $foundPaths = @()
    if ($Path -match '\*') {
        if ($Path -match '^(HKLM|HKLM64|WOW6432|HKU):\\(.+)$') {
            $prefix = $Matches[1]; $pattern = $Matches[2]
            $parentPaths = @()
            switch ($prefix) {
                "HKLM"    { $parentPaths += "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" }
                "HKLM64"  { $parentPaths += "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" }
                "WOW6432" { $parentPaths += "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" }
                "HKU" {
                    if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) { New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue | Out-Null }
                    $userSIDs = Get-ChildItem "HKU:\" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-' -and $_.PSChildName -notmatch '_Classes$' }
                    foreach ($sid in $userSIDs) { $parentPaths += "HKU:\$($sid.PSChildName)\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" }
                }
            }
            foreach ($parentPath in $parentPaths) {
                if (Test-Path $parentPath) {
                    $matchingKeys = Get-ChildItem $parentPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like $pattern }
                    foreach ($key in $matchingKeys) { $foundPaths += $key.PSPath -replace 'Microsoft\.PowerShell\.Core\\Registry::', '' }
                }
            }
        }
    }
    else {
        if ($Path -match '^HKLM:\\(.+)$') { $p = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($Matches[1])"; if (Test-Path $p) { $foundPaths += $p } }
        elseif ($Path -match '^HKLM64:\\(.+)$') { $p = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($Matches[1])"; if (Test-Path $p) { $foundPaths += $p } }
        elseif ($Path -match '^WOW6432:\\(.+)$') { $p = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($Matches[1])"; if (Test-Path $p) { $foundPaths += $p } }
    }
    return $foundPaths
}
#endregion

#region SOFTWARE TARGET DEFINITIONS
$zombieTargets = @(
    @{
        Name          = "Opera Browser"
        Category      = "Unauthorized"
        DetectionType = "Registry"
        RegistryPaths = @("HKU:\Opera*")
        FilePaths     = @()
        Enabled       = $true
    },
    @{
        Name          = "Yandex Browser"
        Category      = "Unauthorized"
        DetectionType = "Registry"
        RegistryPaths = @("HKU:\YandexBrowser")
        FilePaths     = @()
        Enabled       = $true
    },
    @{
        Name          = "GIMP 2"
        Category      = "Unauthorized"
        DetectionType = "Both"
        RegistryPaths = @("HKLM:\GIMP-2_is1", "HKU:\GIMP-2_is1")
        FilePaths     = @("C:\Program Files\GIMP 2\bin\gimp-2.10.exe")
        Enabled       = $true
    },
    @{
        Name          = "Mozilla Thunderbird ESR"
        Category      = "Unauthorized"
        DetectionType = "Both"
        RegistryPaths = @("HKLM:\Mozilla Thunderbird*", "HKLM64:\MozillaMaintenanceService")
        FilePaths     = @("C:\Program Files\Mozilla Thunderbird\crashhelper.exe")
        Enabled       = $true
    },
    @{
        Name          = ".NET 6.0 Runtime (End of Life)"
        Category      = "EndOfLife"
        DetectionType = "FilePath"
        RegistryPaths = @()
        FilePaths     = @("C:\Program Files\dotnet\shared\Microsoft.NETCore.App\6.0.36\.version")
        Enabled       = $true
    },
    @{
        Name          = "Microsoft Silverlight"
        Category      = "EndOfSupport"
        DetectionType = "Registry"
        RegistryPaths = @("HKLM:\{89F4137D-6C26-4A84-BDB8-2E5A4BB71E00}")
        FilePaths     = @()
        Enabled       = $true
    }
)
#endregion

try {
    Write-Log "Starting Zombie Software Remediation"
    foreach ($target in $zombieTargets) {
        if (-not $target.Enabled) { continue }
        Write-Log "Processing: $($target.Name)"
        
        if ($target.DetectionType -eq "Registry" -or $target.DetectionType -eq "Both") {
            $resolvedPaths = foreach ($rp in $target.RegistryPaths) { Resolve-RegistryPaths -Path $rp }
            foreach ($resolved in $resolvedPaths) {
                if (Invoke-SilentUninstall -RegistryKeyPath $resolved -TargetName $target.Name) {
                    Write-Log "  Successfully uninstalled via registry"
                }
            }
        }

        if ($target.DetectionType -eq "FilePath" -or $target.DetectionType -eq "Both") {
            foreach ($fp in $target.FilePaths) {
                if (Test-Path $fp) {
                    $appFolder = Split-Path $fp -Parent
                    if (Remove-ApplicationFolder -FolderPath $appFolder) {
                        Write-Log "  Successfully removed application folder"
                    }
                }
            }
        }
    }
    Write-Log "Remediation complete."
    exit 0
}
catch {
    Write-Log "Critical error during remediation: $($_.Exception.Message)" -Level ERROR
    exit 1
}
