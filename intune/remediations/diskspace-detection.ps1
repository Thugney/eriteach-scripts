<#
.SYNOPSIS
    Detects low disk space on C: drive using dual thresholds.

.DESCRIPTION
    Detection script for Intune Proactive Remediations.
    Uses both percentage and absolute threshold to identify devices with low disk space.
    - Below 10% free OR below 15GB = Non-compliant (exit 1)
    - Otherwise = Compliant (exit 0)
    Works well for devices with 100-250GB disks where user data is stored in OneDrive.

.NOTES
    Author: Eriteach
    Version: 1.0
    Intune Run Context: System
#>

# Thresholds - adjust as needed
$MinFreeSpaceGB = 15          # Minimum GB free
$MinFreeSpacePercent = 10     # Minimum percent free

try {
    # Get disk info via WMI (more reliable than Get-PSDrive)
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop

    if (-not $disk) {
        Write-Output "ERROR: Could not get disk information"
        exit 1
    }

    # Calculate values
    $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $totalSpaceGB = [math]::Round($disk.Size / 1GB, 2)
    $freeSpacePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)

    # Evaluate compliance
    $isCompliant = ($freeSpaceGB -ge $MinFreeSpaceGB) -and ($freeSpacePercent -ge $MinFreeSpacePercent)

    if ($isCompliant) {
        Write-Output "Compliant: $freeSpaceGB GB free ($freeSpacePercent%) of $totalSpaceGB GB"
        exit 0
    }
    else {
        Write-Output "Non-Compliant: $freeSpaceGB GB free ($freeSpacePercent%) of $totalSpaceGB GB | Threshold: ${MinFreeSpaceGB}GB or ${MinFreeSpacePercent}%"
        exit 1
    }
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
