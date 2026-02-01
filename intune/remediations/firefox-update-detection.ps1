<#
.SYNOPSIS
Detects if Firefox needs updating.

.DESCRIPTION
Compares installed Firefox version against Mozilla's product API.
Returns exit 1 if update needed, exit 0 if up to date or not installed.

.NOTES
Author: Eriteach
Version: 1.0
Intune Run Context: System
#>

# Get installed Firefox version from registry
$firefox = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" |
    Where-Object { $_.DisplayName -like "Mozilla Firefox*" }

if (-not $firefox) {
    Write-Output "Firefox not installed"
    exit 0
}

$installedVersion = [version]($firefox.DisplayVersion -replace '[^0-9.]')

# Get latest version from Mozilla API
try {
    $response = Invoke-RestMethod -Uri "https://product-details.mozilla.org/1.0/firefox_versions.json"
    $latestVersion = [version]$response.LATEST_FIREFOX_VERSION
}
catch {
    Write-Output "Could not check latest version: $_"
    exit 0
}

# Compare versions
if ($installedVersion -lt $latestVersion) {
    Write-Output "Update needed: $installedVersion -> $latestVersion"
    exit 1
}

Write-Output "Firefox is up to date: $installedVersion"
exit 0
