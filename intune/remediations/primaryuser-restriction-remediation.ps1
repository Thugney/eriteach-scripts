<#
.SYNOPSIS
Restricts interactive login to only the Intune primary user and Administrators.

.DESCRIPTION
Configures the Windows SeInteractiveLogonRight policy to only allow the device's
Intune primary user and local Administrators to log in interactively. This prevents
unauthorized device handoffs where users take over colleagues' devices without
going through IT.

The script:
1. Reads the primary user UPN from Intune enrollment registry keys
2. Falls back to dsregcmd if registry lookup fails
3. Translates the UPN to a Windows SID
4. Backs up the current security policy
5. Sets SeInteractiveLogonRight to only allow primary user SID + Administrators
6. Applies the policy with secedit and runs gpupdate

Use -WhatIf parameter to see what changes would be made without applying them.

.PARAMETER WhatIf
Shows what the script would do without making any changes.

.NOTES
Author: Eriteach
Version: 1.0
Intune Run Context: System
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf = $false
)

function Write-OutputLog {
    param([string]$Message)
    Write-Output $Message
}

try {
    Write-OutputLog "Starting Primary User Login Restriction Remediation"

    # Get primary user UPN from Intune enrollment registry
    $primaryUserUPN = $null
    $enrollmentPath = "HKLM:\SOFTWARE\Microsoft\Enrollments"
    $enrollmentKeys = Get-ChildItem -Path $enrollmentPath -ErrorAction SilentlyContinue

    foreach ($key in $enrollmentKeys) {
        $keyPath = $key.PSPath
        try {
            $upn = Get-ItemProperty -Path $keyPath -Name "UPN" -ErrorAction SilentlyContinue
            if ($upn.UPN) {
                $primaryUserUPN = $upn.UPN
                Write-OutputLog "Found primary user from Intune enrollment: $primaryUserUPN"
                break
            }
        } catch {
            continue
        }
    }

    # Fallback: dsregcmd (machine-level)
    if (-not $primaryUserUPN) {
        try {
            $dsregStatus = dsregcmd /status
            $userEmailLine = $dsregStatus | Where-Object { $_ -match "UserEmail\s*:" }
            if ($userEmailLine) {
                $primaryUserUPN = ($userEmailLine -split ":")[1].Trim()
                Write-OutputLog "Found primary user from dsregcmd: $primaryUserUPN"
            }
        } catch {}
    }

    if (-not $primaryUserUPN) {
        throw "Could not determine primary user for this device"
    }

    # Translate UPN to SID using NTAccount
    try {
        $account = "AzureAD\$primaryUserUPN"
        $ntAccount = New-Object System.Security.Principal.NTAccount($account)
        $userSID = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
        Write-OutputLog "Found primary user SID: $userSID"
    } catch {
        throw "Could not determine user SID for primary user: $primaryUserUPN - $($_.Exception.Message)"
    }

    if ($WhatIf) {
        Write-OutputLog "WHATIF: Would configure login rights for user SID: $userSID (primary: $primaryUserUPN) + admins"
        Write-OutputLog "WHATIF: Would block all other users from logging in"
        exit 0
    }

    # Export and backup current security policy
    $tempFile = "$env:TEMP\secpol.cfg"
    $backupFile = "$env:TEMP\secpol_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').cfg"

    Write-OutputLog "Exporting current security policy..."
    secedit /export /cfg $tempFile /quiet

    if (Test-Path $tempFile) {
        Copy-Item $tempFile $backupFile
        Write-OutputLog "Security policy backed up to: $backupFile"

        # Read and update policy
        $policyContent = Get-Content $tempFile
        $newPolicyContent = @()
        $logonRightSet = $false

        foreach ($line in $policyContent) {
            if ($line -match "^SeInteractiveLogonRight\s*=") {
                $newLine = "SeInteractiveLogonRight = *$userSID,*S-1-5-32-544"
                $newPolicyContent += $newLine
                $logonRightSet = $true
                Write-OutputLog "Updated SeInteractiveLogonRight: $newLine"
            } else {
                $newPolicyContent += $line
            }
        }

        if (-not $logonRightSet) {
            $newPolicyContent += "SeInteractiveLogonRight = *$userSID,*S-1-5-32-544"
            Write-OutputLog "Added SeInteractiveLogonRight for primary user and administrators"
        }

        # Save and apply new policy
        $newPolicyContent | Set-Content $tempFile
        Write-OutputLog "Applying new security policy..."
        secedit /configure /db secedit.sdb /cfg $tempFile /quiet
        gpupdate /force

        if ($LASTEXITCODE -eq 0) {
            Write-OutputLog "Security policy applied successfully!"
            Write-OutputLog "Only the primary user ($primaryUserUPN) and local Administrators can now log in."
            Write-OutputLog "Restore if needed: secedit /configure /db secedit.sdb /cfg $backupFile /quiet"
        } else {
            throw "Failed to apply security policy. Exit code: $LASTEXITCODE"
        }

        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

    } else {
        throw "Failed to export current security policy"
    }

} catch {
    Write-OutputLog "Remediation failed: $($_.Exception.Message)"
    exit 1
}

Write-OutputLog "Remediation completed successfully."
exit 0
