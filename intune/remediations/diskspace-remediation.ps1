<#
.SYNOPSIS
    Silently cleans C: drive without GUI interaction.

.DESCRIPTION
    Remediation script for Intune Proactive Remediations.
    Completely silent - no user prompts or popups.
    Cleans: temp files, Windows Update cache, Recycle Bin, prefetch, logs, WER, thumbnails.
    Avoids cleanmgr.exe which requires desktop interaction.

.NOTES
    Author: Eriteach
    Version: 1.0
    Intune Run Context: System
    Log: C:\ProgramData\Intune\Logs\DiskSpace-Remediation.log
#>

$ErrorActionPreference = 'SilentlyContinue'

$LogPath = "C:\ProgramData\Intune\Logs\DiskSpace-Remediation.log"
$LogDir = Split-Path $LogPath -Parent

# Create log folder
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$Timestamp - $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
}

function Get-FolderSizeMB {
    param([string]$Path)
    if (Test-Path $Path) {
        $Size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        return [math]::Round(($Size / 1MB), 2)
    }
    return 0
}

function Clear-FolderContent {
    param(
        [string]$Path,
        [string]$Description,
        [int]$DaysOld = 0
    )

    if (-not (Test-Path $Path)) { return 0 }

    $SizeBefore = Get-FolderSizeMB -Path $Path

    try {
        if ($DaysOld -gt 0) {
            # Delete only files older than X days
            $CutoffDate = (Get-Date).AddDays(-$DaysOld)
            Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $CutoffDate } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            # Delete everything
            Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        $SizeAfter = Get-FolderSizeMB -Path $Path
        $Cleaned = [math]::Round($SizeBefore - $SizeAfter, 2)

        if ($Cleaned -gt 0) {
            Write-Log "$Description : Freed $Cleaned MB"
        }

        return $Cleaned
    }
    catch {
        Write-Log "Error cleaning $Description : $($_.Exception.Message)"
        return 0
    }
}

# Start
Write-Log "=== Starting disk cleanup ==="

$DiskBefore = (Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB
Write-Log "Free space before: $([math]::Round($DiskBefore, 2)) GB"

$TotalCleaned = 0

# 1. Windows Temp
$TotalCleaned += Clear-FolderContent -Path "$env:SystemRoot\Temp" -Description "Windows Temp"

# 2. Prefetch (older than 7 days - keep recent for performance)
$TotalCleaned += Clear-FolderContent -Path "$env:SystemRoot\Prefetch" -Description "Prefetch" -DaysOld 7

# 3. SoftwareDistribution Download (stop/start Windows Update)
try {
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $TotalCleaned += Clear-FolderContent -Path "$env:SystemRoot\SoftwareDistribution\Download" -Description "Windows Update Download"
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
}
catch {
    Write-Log "Error with Windows Update cache: $($_.Exception.Message)"
}

# 4. Windows Logs (older than 14 days)
$TotalCleaned += Clear-FolderContent -Path "$env:SystemRoot\Logs" -Description "Windows Logs" -DaysOld 14

# 5. All user profiles - Temp folders
$UserProfiles = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }

foreach ($Profile in $UserProfiles) {
    $UserTemp = Join-Path $Profile.FullName "AppData\Local\Temp"
    $TotalCleaned += Clear-FolderContent -Path $UserTemp -Description "User Temp ($($Profile.Name))"
}

# 6. Recycle Bin - silent clear
try {
    $Shell = New-Object -ComObject Shell.Application
    $RecycleBin = $Shell.NameSpace(0xA)
    $RecycleItems = $RecycleBin.Items()

    if ($RecycleItems.Count -gt 0) {
        $RecycleSizeMB = 0
        foreach ($Item in $RecycleItems) {
            $RecycleSizeMB += $Item.Size / 1MB
        }

        # Clear via cmdlet - completely silent
        Clear-RecycleBin -DriveLetter C -Force -ErrorAction SilentlyContinue

        $TotalCleaned += [math]::Round($RecycleSizeMB, 2)
        Write-Log "Recycle Bin: Freed $([math]::Round($RecycleSizeMB, 2)) MB"
    }
}
catch {
    Write-Log "Error with Recycle Bin: $($_.Exception.Message)"
}

# 7. Windows Error Reporting
$TotalCleaned += Clear-FolderContent -Path "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" -Description "Windows Error Reports"
$TotalCleaned += Clear-FolderContent -Path "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" -Description "Windows Error Archive"

# 8. Delivery Optimization cache
$TotalCleaned += Clear-FolderContent -Path "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization" -Description "Delivery Optimization"

# 9. Thumbnail cache (all users)
foreach ($Profile in $UserProfiles) {
    $ThumbPath = Join-Path $Profile.FullName "AppData\Local\Microsoft\Windows\Explorer"
    if (Test-Path $ThumbPath) {
        Get-ChildItem -Path $ThumbPath -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# Result
$DiskAfter = (Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB
$ActualFreed = [math]::Round($DiskAfter - $DiskBefore, 2)

Write-Log "=== Cleanup completed ==="
Write-Log "Estimated freed: $TotalCleaned MB"
Write-Log "Actual freed: $([math]::Round($ActualFreed * 1024, 2)) MB"
Write-Log "Free space after: $([math]::Round($DiskAfter, 2)) GB"

# Output for Intune
Write-Output "Cleanup completed. Freed: $([math]::Round($ActualFreed * 1024, 2)) MB. Free space: $([math]::Round($DiskAfter, 2)) GB"
exit 0
