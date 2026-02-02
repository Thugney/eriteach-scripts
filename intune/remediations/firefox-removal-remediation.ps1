<#
.SYNOPSIS
Proactive Remediation - Removes Firefox installations

.DESCRIPTION
Removes all Firefox installations with detailed output for Intune reports.

Cleanup steps:
1. Stop all Firefox processes
2. Uninstall via registry (handles both EXE and MSI)
3. Remove Program Files directories
4. Remove user profile data
5. Delete shortcuts (Desktop and Start Menu)
6. Remove MozillaMaintenance service
7. Unregister scheduled tasks

Exit 0 = Success
Exit 1 = Failed (some items could not be removed)

.NOTES
Author: Eriteach
Version: 2.0
Intune Run Context: System (64-bit)
#>

$ErrorActionPreference = "Continue"
$removedItems = @()
$failedItems = @()

# Stop Processes
$firefoxProcesses = @("firefox", "firefox-esr", "firefoxdeveloperedition", "plugin-container", "crashreporter", "updater", "maintenanceservice")

foreach ($proc in $firefoxProcesses) {
    $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
    if ($running) {
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        $removedItems += "Stopped process: $proc ($($running.Count) instance(s))"
    }
}
Start-Sleep -Seconds 2

# Uninstall via Registry
$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($regPath in $uninstallPaths) {
    if (-not (Test-Path $regPath)) { continue }

    $firefoxApps = Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    } | Where-Object { $_.DisplayName -like "*Firefox*" }

    foreach ($app in $firefoxApps) {
        $appName = $app.DisplayName
        $uninstallString = $app.UninstallString

        if ($uninstallString -match 'helper\.exe') {
            $helperPath = $uninstallString -replace '"', ''
            if (Test-Path $helperPath) {
                try {
                    Start-Process -FilePath $helperPath -ArgumentList "/S" -Wait -NoNewWindow -ErrorAction Stop
                    $removedItems += "Uninstalled: $appName"
                } catch {
                    $failedItems += "Failed to uninstall: $appName - $($_.Exception.Message)"
                }
            }
        } elseif ($uninstallString -match 'msiexec') {
            $productCode = $uninstallString -replace '.*(\{[A-F0-9-]+\}).*', '$1'
            if ($productCode -match '\{[A-F0-9-]+\}') {
                try {
                    Start-Process "msiexec.exe" -ArgumentList "/x `"$productCode`" /qn /norestart" -Wait -NoNewWindow
                    $removedItems += "Uninstalled (MSI): $appName"
                } catch {
                    $failedItems += "Failed MSI uninstall: $appName"
                }
            }
        }
    }
}

# Remove Directories
$systemDirs = @(
    "$env:ProgramFiles\Mozilla Firefox",
    "${env:ProgramFiles(x86)}\Mozilla Firefox",
    "$env:ProgramFiles\Firefox Developer Edition",
    "${env:ProgramFiles(x86)}\Firefox Developer Edition",
    "$env:ProgramData\Mozilla"
)

foreach ($dir in $systemDirs) {
    if (Test-Path $dir) {
        try {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction Stop
            $removedItems += "Removed directory: $dir"
        } catch {
            $failedItems += "Failed to remove: $dir"
        }
    }
}

# User profile directories
$userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }

foreach ($profile in $userProfiles) {
    $userDirs = @(
        "$($profile.FullName)\AppData\Local\Mozilla Firefox",
        "$($profile.FullName)\AppData\Local\Mozilla",
        "$($profile.FullName)\AppData\Roaming\Mozilla\Firefox"
    )
    foreach ($dir in $userDirs) {
        if (Test-Path $dir) {
            try {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction Stop
                $removedItems += "Removed user data ($($profile.Name)): $dir"
            } catch {
                $failedItems += "Failed to remove ($($profile.Name)): $dir"
            }
        }
    }
}

# Remove Shortcuts
$shortcutPaths = @(
    "$env:PUBLIC\Desktop\*Firefox*.lnk",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\*Firefox*.lnk",
    "C:\Users\*\Desktop\*Firefox*.lnk"
)

foreach ($path in $shortcutPaths) {
    $shortcuts = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
    foreach ($shortcut in $shortcuts) {
        Remove-Item $shortcut.FullName -Force -ErrorAction SilentlyContinue
        $removedItems += "Removed shortcut: $($shortcut.Name)"
    }
}

# Remove Services
$service = Get-Service -Name "MozillaMaintenance" -ErrorAction SilentlyContinue
if ($service) {
    Stop-Service -Name "MozillaMaintenance" -Force -ErrorAction SilentlyContinue
    sc.exe delete "MozillaMaintenance" | Out-Null
    $removedItems += "Removed service: MozillaMaintenance"
}

# Remove Scheduled Tasks
$tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*Firefox*" -or $_.TaskName -like "*Mozilla*" }
foreach ($task in $tasks) {
    Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    $removedItems += "Removed task: $($task.TaskName)"
}

# Output Results
Write-Output "====== FIREFOX REMOVAL RESULTS ======"
Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output ""

if ($removedItems.Count -gt 0) {
    Write-Output "REMOVED ($($removedItems.Count) items):"
    $removedItems | ForEach-Object { Write-Output "  [OK] $_" }
}

if ($failedItems.Count -gt 0) {
    Write-Output ""
    Write-Output "FAILED ($($failedItems.Count) items):"
    $failedItems | ForEach-Object { Write-Output "  [FAIL] $_" }
}

if ($removedItems.Count -eq 0 -and $failedItems.Count -eq 0) {
    Write-Output "No Firefox components found to remove"
}

Write-Output ""
Write-Output "====== END OF REPORT ======"

if ($failedItems.Count -gt 0) {
    exit 1
} else {
    exit 0
}
