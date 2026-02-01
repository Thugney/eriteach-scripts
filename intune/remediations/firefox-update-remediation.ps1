<#
.SYNOPSIS
Installs latest Firefox version.

.DESCRIPTION
Downloads Firefox installer from Mozilla and runs silent install.
Cleans up installer after completion.

.NOTES
Author: Eriteach
Version: 1.0
Intune Run Context: System
#>

$installerPath = "$env:TEMP\FirefoxSetup.exe"
$downloadUrl = "https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US"

# Download latest Firefox installer
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
}
catch {
    Write-Output "Download failed: $_"
    exit 1
}

# Silent install
$process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru

if ($process.ExitCode -eq 0) {
    Write-Output "Firefox updated successfully"
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    exit 0
}
else {
    Write-Output "Installation failed with exit code: $($process.ExitCode)"
    exit 1
}
