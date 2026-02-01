<#
 .Descriptions
    remediation skript for Intune Proactive Remediation
    skriptet aviinstallere funnet apper 
    
    
.Author
    Robwol

#>

# CONFIGURATION SECTION - MUST MATCH DETECTION SCRIPT

$AppDisplayName = "Zoom"           # Application display name (must match detection script)
$AppPublisher = ""                        # Optional: Publisher name for validation
$AppProductCode = "{86B70A45-00A6-4CBD-97A8-464A1254D179}" 
$AppUninstallString = ""                  # Optional: Specific uninstall string
$UsePartialMatch = $true                  # Must match detection script setting

# UNINSTALL CONFIGURATION
$UninstallTimeout = 300                   # Timeout in seconds for uninstall process
$ForceCloseProcesses = $true             # Force close related processes before uninstall
$ProcessNamesToClose = @()               # Add specific process names if known (without .exe)
$CustomUninstallArgs = ""                # Additional arguments for uninstall command
$VerifyUninstall = $true                 # Re-check if app was successfully removed

# LOGGING CONFIGURATION
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = "$LogPath\AppRemediation_$(Get-Date -Format 'yyyyMMdd').log"


function Write-LogEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] [$Level] $Message"
    
    # Create log directory if it doesn't exist
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $LogEntry -Force
    
    # Write to host for immediate feedback
    switch ($Level) {
        "INFO" { Write-Host $LogEntry -ForegroundColor Green }
        "WARN" { Write-Host $LogEntry -ForegroundColor Yellow }
        "ERROR" { Write-Host $LogEntry -ForegroundColor Red }
    }
}

function Find-InstalledApplication {
    param(
        [string]$DisplayName,
        [string]$Publisher,
        [string]$ProductCode,
        [bool]$PartialMatch
    )
    
    Write-LogEntry "Searching for installed application..." "INFO"
    
    # Registry paths to check
    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($Path in $RegistryPaths) {
        try {
            $InstalledApps = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
            
            foreach ($App in $InstalledApps) {
                $Match = $false
                
                # Check by Display Name
                if (-not [string]::IsNullOrEmpty($DisplayName)) {
                    if ($PartialMatch) {
                        $Match = $App.DisplayName -like "*$DisplayName*"
                    } else {
                        $Match = $App.DisplayName -eq $DisplayName
                    }
                }
                
                # Additional validation checks
                if ($Match) {
                    # Validate Publisher if specified
                    if (-not [string]::IsNullOrEmpty($Publisher) -and $App.Publisher -notlike "*$Publisher*") {
                        $Match = $false
                    }
                    
                    # Validate Product Code if specified
                    if (-not [string]::IsNullOrEmpty($ProductCode) -and $App.PSChildName -ne $ProductCode) {
                        $Match = $false
                    }
                    
                    if ($Match) {
                        Write-LogEntry "Found application: $($App.DisplayName) (Version: $($App.DisplayVersion))" "INFO"
                        return $App
                    }
                }
            }
        }
        catch {
            Write-LogEntry "Error checking registry path $Path`: $($_.Exception.Message)" "ERROR"
        }
    }
    
    return $null
}

function Stop-RelatedProcesses {
    param(
        [string[]]$ProcessNames,
        [string]$AppName
    )
    
    Write-LogEntry "Checking for processes to terminate..." "INFO"
    
    # Add common process names based on app name if no specific processes provided
    if ($ProcessNames.Count -eq 0 -and -not [string]::IsNullOrEmpty($AppName)) {
        $ProcessNames = @(
            $AppName.Replace(" ", ""),
            $AppName.Replace(" ", "."),
            $AppName.Split(" ")[0]
        )
    }
    
    foreach ($ProcessName in $ProcessNames) {
        try {
            $Processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
            if ($Processes) {
                Write-LogEntry "Found $($Processes.Count) instance(s) of process: $ProcessName" "WARN"
                foreach ($Process in $Processes) {
                    try {
                        $Process.CloseMainWindow()
                        Start-Sleep -Seconds 3
                        
                        if (-not $Process.HasExited) {
                            Write-LogEntry "Force killing process: $($Process.ProcessName) (PID: $($Process.Id))" "WARN"
                            $Process.Kill()
                        } else {
                            Write-LogEntry "Process closed gracefully: $($Process.ProcessName)" "INFO"
                        }
                    }
                    catch {
                        Write-LogEntry "Error stopping process $($Process.ProcessName): $($_.Exception.Message)" "ERROR"
                    }
                }
            }
        }
        catch {
            Write-LogEntry "Error checking for process $ProcessName`: $($_.Exception.Message)" "WARN"
        }
    }
}

function Invoke-ApplicationUninstall {
    param(
        [PSObject]$Application,
        [string]$CustomArgs,
        [int]$TimeoutSeconds
    )
    
    Write-LogEntry "Starting uninstall process for: $($Application.DisplayName)" "INFO"
    
    $UninstallString = $Application.UninstallString
    $QuietUninstallString = $Application.QuietUninstallString
    $ProductCode = $Application.PSChildName
    
    # Determine uninstall method and command
    $UninstallCommand = ""
    $UninstallArgs = ""
    $IsMSI = $false
    
    # Check if it's an MSI package (Product Code is GUID format)
    if ($ProductCode -match "^\{[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}\}$") {
        Write-LogEntry "Detected MSI package with Product Code: $ProductCode" "INFO"
        $IsMSI = $true
        $UninstallCommand = "msiexec.exe"
        $UninstallArgs = "/x `"$ProductCode`" /quiet /norestart /l*v `"$LogPath\MSI_Uninstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log`""
    }
    # Use QuietUninstallString if available
    elseif (-not [string]::IsNullOrEmpty($QuietUninstallString)) {
        Write-LogEntry "Using QuietUninstallString: $QuietUninstallString" "INFO"
        if ($QuietUninstallString -match '^"([^"]+)"(.*)') {
            $UninstallCommand = $matches[1]
            $UninstallArgs = $matches[2].Trim()
        } else {
            $Parts = $QuietUninstallString.Split(' ', 2)
            $UninstallCommand = $Parts[0]
            $UninstallArgs = if ($Parts.Length -gt 1) { $Parts[1] } else { "" }
        }
    }
    # Use regular UninstallString with silent switches
    elseif (-not [string]::IsNullOrEmpty($UninstallString)) {
        Write-LogEntry "Using UninstallString with silent parameters: $UninstallString" "INFO"
        if ($UninstallString -match '^"([^"]+)"(.*)') {
            $UninstallCommand = $matches[1]
            $UninstallArgs = $matches[2].Trim()
        } else {
            $Parts = $UninstallString.Split(' ', 2)
            $UninstallCommand = $Parts[0]
            $UninstallArgs = if ($Parts.Length -gt 1) { $Parts[1] } else { "" }
        }
        
        # Add common silent switches for non-MSI installers
        if (-not $IsMSI) {
            $SilentSwitches = @("/S", "/SILENT", "/VERYSILENT", "/q", "/quiet")
            $HasSilentSwitch = $false
            
            foreach ($Switch in $SilentSwitches) {
                if ($UninstallArgs -like "*$Switch*") {
                    $HasSilentSwitch = $true
                    break
                }
            }
            
            if (-not $HasSilentSwitch) {
                $UninstallArgs += " /S /SILENT"
                Write-LogEntry "Added silent switches to uninstall arguments" "INFO"
            }
        }
    }
    else {
        Write-LogEntry "No uninstall string found for application" "ERROR"
        return $false
    }
    
    # Add custom arguments if provided
    if (-not [string]::IsNullOrEmpty($CustomArgs)) {
        $UninstallArgs += " $CustomArgs"
    }
    
    Write-LogEntry "Uninstall Command: $UninstallCommand" "INFO"
    Write-LogEntry "Uninstall Arguments: $UninstallArgs" "INFO"
    
    # Execute uninstall command
    try {
        $ProcessStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $ProcessStartInfo.FileName = $UninstallCommand
        $ProcessStartInfo.Arguments = $UninstallArgs
        $ProcessStartInfo.UseShellExecute = $false
        $ProcessStartInfo.RedirectStandardOutput = $true
        $ProcessStartInfo.RedirectStandardError = $true
        $ProcessStartInfo.CreateNoWindow = $true
        $ProcessStartInfo.WorkingDirectory = $env:SystemRoot
        
        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $ProcessStartInfo
        
        Write-LogEntry "Starting uninstall process..." "INFO"
        $Process.Start() | Out-Null
        
        # Wait for process completion with timeout
        $Completed = $Process.WaitForExit($TimeoutSeconds * 1000)
        
        if ($Completed) {
            $ExitCode = $Process.ExitCode
            $StdOut = $Process.StandardOutput.ReadToEnd()
            $StdErr = $Process.StandardError.ReadToEnd()
            
            Write-LogEntry "Uninstall process completed with exit code: $ExitCode" "INFO"
            
            if (-not [string]::IsNullOrEmpty($StdOut)) {
                Write-LogEntry "Standard Output: $StdOut" "INFO"
            }
            
            if (-not [string]::IsNullOrEmpty($StdErr)) {
                Write-LogEntry "Standard Error: $StdErr" "WARN"
            }
            
            # Common successful exit codes
            $SuccessExitCodes = @(0, 3010, 1641)  # 0=Success, 3010=Reboot required, 1641=Reboot initiated
            
            if ($ExitCode -in $SuccessExitCodes) {
                Write-LogEntry "Uninstall completed successfully" "INFO"
                return $true
            } else {
                Write-LogEntry "Uninstall failed with exit code: $ExitCode" "ERROR"
                return $false
            }
        } else {
            Write-LogEntry "Uninstall process timed out after $TimeoutSeconds seconds" "ERROR"
            try {
                $Process.Kill()
                Write-LogEntry "Terminated uninstall process due to timeout" "WARN"
            }
            catch {
                Write-LogEntry "Failed to terminate uninstall process: $($_.Exception.Message)" "ERROR"
            }
            return $false
        }
    }
    catch {
        Write-LogEntry "Error executing uninstall command: $($_.Exception.Message)" "ERROR"
        return $false
    }
    finally {
        if ($Process) {
            $Process.Dispose()
        }
    }
}

function Test-UninstallSuccess {
    param(
        [string]$DisplayName,
        [string]$Publisher,
        [string]$ProductCode,
        [bool]$PartialMatch
    )
    
    Write-LogEntry "Verifying uninstall success..." "INFO"
    Start-Sleep -Seconds 5  # Wait a moment for system to update
    
    $RemainingApp = Find-InstalledApplication -DisplayName $DisplayName -Publisher $Publisher -ProductCode $ProductCode -PartialMatch $PartialMatch
    
    if ($RemainingApp) {
        Write-LogEntry "Application is still installed after uninstall attempt" "ERROR"
        return $false
    } else {
        Write-LogEntry "Application successfully removed from system" "INFO"
        return $true
    }
}

# ===================================================================
# MAIN EXECUTION
# ===================================================================

Write-LogEntry "=== Starting Application Remediation ===" "INFO"
Write-LogEntry "Target Application: $AppDisplayName" "INFO"

$RemediationSuccess = $false

try {
    # Step 1: Find the application
    $InstalledApp = Find-InstalledApplication -DisplayName $AppDisplayName -Publisher $AppPublisher -ProductCode $AppProductCode -PartialMatch $UsePartialMatch
    
    if (-not $InstalledApp) {
        Write-LogEntry "Application not found on system - no remediation needed" "INFO"
        Write-LogEntry "=== Remediation Complete - Success ===" "INFO"
        exit 0
    }
    
    # Step 2: Stop related processes if configured
    if ($ForceCloseProcesses) {
        Stop-RelatedProcesses -ProcessNames $ProcessNamesToClose -AppName $AppDisplayName
    }
    
    # Step 3: Uninstall the application
    $UninstallSuccess = Invoke-ApplicationUninstall -Application $InstalledApp -CustomArgs $CustomUninstallArgs -TimeoutSeconds $UninstallTimeout
    
    if ($UninstallSuccess) {
        # Step 4: Verify uninstall success if configured
        if ($VerifyUninstall) {
            $RemediationSuccess = Test-UninstallSuccess -DisplayName $AppDisplayName -Publisher $AppPublisher -ProductCode $AppProductCode -PartialMatch $UsePartialMatch
        } else {
            $RemediationSuccess = $true
        }
    }
    
    # Final Result
    if ($RemediationSuccess) {
        Write-LogEntry "REMEDIATION RESULT: Application '$AppDisplayName' successfully uninstalled" "INFO"
        Write-LogEntry "=== Remediation Complete - Success ===" "INFO"
        exit 0
    } else {
        Write-LogEntry "REMEDIATION RESULT: Failed to uninstall application '$AppDisplayName'" "ERROR"
        Write-LogEntry "=== Remediation Complete - Failed ===" "ERROR"
        exit 1
    }
}
catch {
    Write-LogEntry "Critical error during remediation: $($_.Exception.Message)" "ERROR"
    Write-LogEntry "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    Write-LogEntry "=== Remediation Complete - Failed ===" "ERROR"
    exit 1
}