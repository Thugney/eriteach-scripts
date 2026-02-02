<#
.SYNOPSIS
Proactive Remediation - Detects Firefox installations

.DESCRIPTION
Checks all possible Firefox installation locations:
- Registry (HKLM 64-bit, HKLM 32-bit, HKCU)
- Program Files (64-bit and 32-bit)
- User profiles (AppData\Local)

Output is displayed in Intune reports.

Exit 0 = Compliant (no Firefox)
Exit 1 = Non-compliant (Firefox found)

.NOTES
Author: Eriteach
Version: 2.0
Intune Run Context: System (64-bit)
#>

$findings = @()

# Registry check
$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($path in $uninstallPaths) {
    if (Test-Path $path) {
        $apps = Get-ItemProperty "$path\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*Firefox*" }
        foreach ($app in $apps) {
            $findings += "Registry: $($app.DisplayName) v$($app.DisplayVersion)"
        }
    }
}

# Program Files check
$programPaths = @(
    "$env:ProgramFiles\Mozilla Firefox",
    "${env:ProgramFiles(x86)}\Mozilla Firefox",
    "$env:ProgramFiles\Firefox Developer Edition",
    "${env:ProgramFiles(x86)}\Firefox Developer Edition"
)

foreach ($path in $programPaths) {
    if (Test-Path "$path\firefox.exe") {
        $version = (Get-Item "$path\firefox.exe").VersionInfo.ProductVersion
        $findings += "Program Files: $path (v$version)"
    }
}

# User Profile check
$userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }

foreach ($profile in $userProfiles) {
    $userPaths = @(
        "$($profile.FullName)\AppData\Local\Mozilla Firefox",
        "$($profile.FullName)\AppData\Local\Firefox Developer Edition"
    )
    foreach ($path in $userPaths) {
        if (Test-Path "$path\firefox.exe") {
            $findings += "User Install ($($profile.Name)): $path"
        }
    }
}

# Output Results
if ($findings.Count -gt 0) {
    Write-Output "FIREFOX DETECTED - $($findings.Count) installation(s) found:"
    $findings | ForEach-Object { Write-Output "  - $_" }
    exit 1
} else {
    Write-Output "COMPLIANT - No Firefox installations found"
    exit 0
}
