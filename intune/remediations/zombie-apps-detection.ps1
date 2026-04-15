<#
.SYNOPSIS
    Detection script for unauthorized or end-of-support software ("Zombie Software").

.DESCRIPTION
    Scans the registry (HKLM, WOW6432Node, and HKU for per-user installs) and file paths 
    for unauthorized, end-of-life, or unsupported software. 
    
    Designed for use with Intune Proactive Remediation.

.NOTES
    Author: eriteach
    Version: 1.1
    Intune Run Context: System
#>

$logPath = "C:\ProgramData\Eriteach\Logs\ZombieSoftware-Detect.log"

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

function Test-RegistryPath {
    param([string]$Path)
    $foundPaths = @()
    
    if ($Path -match '^HKLM:\\(.+)$') {
        $fullPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($Matches[1])"
        if (Test-Path $fullPath) { $foundPaths += $fullPath }
    }
    elseif ($Path -match '^HKLM64:\\(.+)$') {
        $fullPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($Matches[1])"
        if (Test-Path $fullPath) { $foundPaths += $fullPath }
    }
    elseif ($Path -match '^WOW6432:\\(.+)$') {
        $fullPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($Matches[1])"
        if (Test-Path $fullPath) { $foundPaths += $fullPath }
    }
    elseif ($Path -match '^HKU:\\(.+)$') {
        $subKey = $Matches[1]
        if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
            New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue | Out-Null
        }
        $userSIDs = Get-ChildItem "HKU:\" -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -match '^S-1-5-21-' -and $_.PSChildName -notmatch '_Classes$' }
        foreach ($sid in $userSIDs) {
            $fullPath = "HKU:\$($sid.PSChildName)\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$subKey"
            if (Test-Path $fullPath) { $foundPaths += $fullPath }
        }
    }
    return $foundPaths
}
#endregion

#region SOFTWARE TARGET DEFINITIONS
$zombieTargets = @(
    @{
        Name          = "Opera Browser"
        Reason        = "Unauthorized browser - Edge is the standard"
        Category      = "Unauthorized"
        DetectionType = "Registry"
        RegistryPaths = @("HKU:\Opera*")
        FilePaths     = @()
        Enabled       = $true
    },
    @{
        Name          = "Yandex Browser"
        Reason        = "Unauthorized browser - Security risk"
        Category      = "Unauthorized"
        DetectionType = "Registry"
        RegistryPaths = @("HKU:\YandexBrowser")
        FilePaths     = @()
        Enabled       = $true
    },
    @{
        Name          = "GIMP 2"
        Reason        = "Unauthorized software - Not in approved catalog"
        Category      = "Unauthorized"
        DetectionType = "Both"
        RegistryPaths = @("HKLM:\GIMP-2_is1", "HKU:\GIMP-2_is1")
        FilePaths     = @("C:\Program Files\GIMP 2\bin\gimp-2.10.exe")
        Enabled       = $true
    },
    @{
        Name          = "Mozilla Thunderbird ESR"
        Reason        = "Unauthorized email client - Outlook is the standard"
        Category      = "Unauthorized"
        DetectionType = "Both"
        RegistryPaths = @("HKLM:\Mozilla Thunderbird*", "HKLM64:\MozillaMaintenanceService")
        FilePaths     = @("C:\Program Files\Mozilla Thunderbird\crashhelper.exe")
        Enabled       = $true
    },
    @{
        Name          = ".NET 6.0 Runtime (End of Life)"
        Reason        = "Deprecated runtime - EOL November 2024"
        Category      = "EndOfLife"
        DetectionType = "FilePath"
        RegistryPaths = @()
        FilePaths     = @("C:\Program Files\dotnet\shared\Microsoft.NETCore.App\6.0.36\.version")
        Enabled       = $true
    },
    @{
        Name          = "Microsoft Silverlight"
        Reason        = "End of Support October 2021"
        Category      = "EndOfSupport"
        DetectionType = "Registry"
        RegistryPaths = @("HKLM:\{89F4137D-6C26-4A84-BDB8-2E5A4BB71E00}")
        FilePaths     = @()
        Enabled       = $true
    }
)
#endregion

try {
    Write-Log "Starting Zombie Software Detection"
    $findings = @()

    foreach ($target in $zombieTargets) {
        if (-not $target.Enabled) { continue }
        $detected = $false
        
        if ($target.DetectionType -eq "Registry" -or $target.DetectionType -eq "Both") {
            foreach ($regPath in $target.RegistryPaths) {
                if ($regPath -match '\*') {
                    if ($regPath -match '^(HKLM|HKLM64|WOW6432|HKU):\\(.+)$') {
                        $prefix = $Matches[1]
                        $pattern = $Matches[2]
                        $parentPaths = @()
                        switch ($prefix) {
                            "HKLM"    { $parentPaths += "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" }
                            "HKLM64"  { $parentPaths += "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" }
                            "WOW6432" { $parentPaths += "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" }
                            "HKU" {
                                if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
                                    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue | Out-Null
                                }
                                $userSIDs = Get-ChildItem "HKU:\" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-' -and $_.PSChildName -notmatch '_Classes$' }
                                foreach ($sid in $userSIDs) { $parentPaths += "HKU:\$($sid.PSChildName)\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" }
                            }
                        }
                        foreach ($parentPath in $parentPaths) {
                            if (Test-Path $parentPath) {
                                $matchingKeys = Get-ChildItem $parentPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like $pattern }
                                if ($matchingKeys) { $detected = $true }
                            }
                        }
                    }
                }
                else {
                    if ((Test-RegistryPath -Path $regPath).Count -gt 0) { $detected = $true }
                }
            }
        }

        if ($target.DetectionType -eq "FilePath" -or $target.DetectionType -eq "Both") {
            foreach ($filePath in $target.FilePaths) {
                if (Test-Path $filePath) { $detected = $true }
            }
        }

        if ($detected) {
            Write-Log "FOUND: $($target.Name) [$($target.Category)]" -Level WARNING
            $findings += $target
        }
    }

    if ($findings.Count -gt 0) {
        Write-Log "Detection complete. Found $($findings.Count) targets."
        exit 1
    }
    Write-Log "Detection complete. No targets found."
    exit 0
}
catch {
    Write-Log "Error during detection: $($_.Exception.Message)" -Level ERROR
    exit 1
}
