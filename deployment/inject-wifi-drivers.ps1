<#
.SYNOPSIS
    Injects HP WiFi drivers into Windows 11 install.wim for offline deployment.

.DESCRIPTION
    Downloads WiFi drivers directly from HP FTP and injects them into install.wim.
    Solves the problem of no WiFi during Windows setup/Autopilot enrollment after reset.

    Supports:
    - Realtek RTL8852/8822/8821 WiFi
    - Intel Wi-Fi 6E AX211
    - HP ProBook G10 driver pack
    - HP WinPE driver pack

    Does NOT require HP CMSL - uses direct download from HP FTP.

.PARAMETER ISOPath
    Path to Windows 11 ISO file or folder with extracted ISO content.

.PARAMETER OutputPath
    Path where modified install.wim will be saved.

.PARAMETER DriverDownloadPath
    Path for temporary driver downloads. Default: C:\HPDrivers

.PARAMETER EditionsToInject
    Windows editions to inject drivers into. Default: Education, Pro, Enterprise

.PARAMETER AllEditions
    If specified, injects into ALL editions including Home.

.EXAMPLE
    # Default: Education, Pro, and Enterprise editions
    .\inject-wifi-drivers.ps1 -ISOPath "C:\Win11.iso" -OutputPath "C:\ModifiedWIM"

.EXAMPLE
    # All editions including Home
    .\inject-wifi-drivers.ps1 -ISOPath "C:\Win11.iso" -OutputPath "C:\ModifiedWIM" -AllEditions

.EXAMPLE
    # Only Education and Enterprise
    .\inject-wifi-drivers.ps1 -ISOPath "C:\Win11.iso" -OutputPath "C:\ModifiedWIM" -EditionsToInject @("Education", "Enterprise")

.NOTES
    Author: Eriteach
    Version: 2.0
    Requirements: Windows ADK (DISM), Administrator privileges
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true)]
    [string]$ISOPath,

    [Parameter(Mandatory=$true)]
    [string]$OutputPath,

    [Parameter(Mandatory=$false)]
    [string]$DriverDownloadPath = "C:\HPDrivers",

    [Parameter(Mandatory=$false)]
    [string[]]$EditionsToInject = @("Education", "Pro", "Enterprise"),

    [Parameter(Mandatory=$false)]
    [switch]$AllEditions,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\ProgramData\Intune\Logs\WiFiDriverInjection.log"
)

#region Functions
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    $logDir = Split-Path -Parent $LogPath
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    Add-Content -Path $LogPath -Value $logEntry

    switch ($Level) {
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default   { Write-Host $logEntry }
    }
}

function Test-AdminPrivileges {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$Description
    )

    Write-Log "Downloading: $Description"
    Write-Log "  URL: $Url"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
        $ProgressPreference = 'Continue'

        if (Test-Path $OutputPath) {
            $size = [math]::Round((Get-Item $OutputPath).Length / 1MB, 2)
            Write-Log "  Downloaded: $size MB" -Level "SUCCESS"
            return $true
        }
    }
    catch {
        Write-Log "  Invoke-WebRequest failed: $_" -Level "WARNING"

        # Fallback: WebClient
        try {
            Write-Log "  Trying WebClient..."
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($Url, $OutputPath)
            $webClient.Dispose()

            if (Test-Path $OutputPath) {
                $size = [math]::Round((Get-Item $OutputPath).Length / 1MB, 2)
                Write-Log "  Downloaded via WebClient: $size MB" -Level "SUCCESS"
                return $true
            }
        }
        catch {
            Write-Log "  WebClient failed: $_" -Level "WARNING"

            # Final fallback: curl.exe
            try {
                Write-Log "  Trying curl.exe..."
                & curl.exe -L -o $OutputPath $Url 2>&1 | Out-Null

                if (Test-Path $OutputPath) {
                    $size = [math]::Round((Get-Item $OutputPath).Length / 1MB, 2)
                    Write-Log "  Downloaded via curl: $size MB" -Level "SUCCESS"
                    return $true
                }
            }
            catch {
                Write-Log "  curl failed: $_" -Level "WARNING"
            }
        }
    }

    Write-Log "  Could not download file" -Level "ERROR"
    return $false
}

function Extract-HPSoftpaq {
    param(
        [string]$SoftpaqPath,
        [string]$ExtractPath
    )

    if (-not (Test-Path $ExtractPath)) {
        New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null
    }

    Write-Log "Extracting: $SoftpaqPath"

    # HP Softpaqs are self-extracting executables
    $process = Start-Process -FilePath $SoftpaqPath -ArgumentList "-e", "-f`"$ExtractPath`"", "-s" -Wait -PassThru -NoNewWindow

    $infFiles = Get-ChildItem -Path $ExtractPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue

    if ($infFiles.Count -gt 0) {
        Write-Log "  Found $($infFiles.Count) driver files (.inf)" -Level "SUCCESS"
        return $true
    }
    else {
        Write-Log "  No .inf files found after extraction" -Level "WARNING"
        return $false
    }
}

function Get-WiFiDrivers {
    param([string]$DownloadPath)

    $driverPath = Join-Path $DownloadPath "WiFiDrivers"
    if (-not (Test-Path $driverPath)) {
        New-Item -Path $driverPath -ItemType Directory -Force | Out-Null
    }

    # Direct HP Softpaq URLs - verified working from HP FTP
    $driverSources = @(
        @{
            Name = "Realtek RTL8852/8822/8821 WiFi"
            URL = "https://ftp.hp.com/pub/softpaq/sp155001-155500/sp155482.exe"
            Folder = "Realtek_WiFi"
        },
        @{
            Name = "Intel Wi-Fi 6E AX211"
            URL = "https://ftp.hp.com/pub/softpaq/sp138501-139000/sp138607.exe"
            Folder = "Intel_AX211"
        },
        @{
            Name = "HP ProBook G10 Driver Pack"
            URL = "https://ftp.hp.com/pub/softpaq/sp145001-145500/sp145027.exe"
            Folder = "HP_ProBook_G10_Pack"
        },
        @{
            Name = "HP WinPE 10/11 Driver Pack"
            URL = "https://ftp.hp.com/pub/softpaq/sp155501-156000/sp155634.exe"
            Folder = "HP_WinPE_Drivers"
        }
    )

    $downloadedPaths = @()

    foreach ($driver in $driverSources) {
        $softpaqFile = Join-Path $DownloadPath "$($driver.Folder).exe"
        $extractPath = Join-Path $driverPath $driver.Folder

        # Skip if already extracted
        if (Test-Path $extractPath) {
            $existingInf = Get-ChildItem -Path $extractPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
            if ($existingInf.Count -gt 0) {
                Write-Log "Using existing: $($driver.Name)"
                $downloadedPaths += $extractPath
                continue
            }
        }

        $downloaded = Download-File -Url $driver.URL -OutputPath $softpaqFile -Description $driver.Name

        if ($downloaded) {
            $extracted = Extract-HPSoftpaq -SoftpaqPath $softpaqFile -ExtractPath $extractPath

            if ($extracted) {
                $downloadedPaths += $extractPath
            }

            Remove-Item -Path $softpaqFile -Force -ErrorAction SilentlyContinue
        }
    }

    return $downloadedPaths
}
#endregion

#region Main Script
try {
    Write-Log "=========================================="
    Write-Log "HP WiFi Driver Injection Script v2.0"
    Write-Log "=========================================="

    if (-not (Test-AdminPrivileges)) {
        throw "Script must be run as Administrator"
    }
    Write-Log "Administrator privileges confirmed"

    # Create directories
    $mountPath = "C:\WIM_Mount"
    @($OutputPath, $DriverDownloadPath, $mountPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
            Write-Log "Created folder: $_"
        }
    }

    # Clean mount point if leftover from previous run
    if ((Get-ChildItem $mountPath -ErrorAction SilentlyContinue).Count -gt 0) {
        Write-Log "Cleaning mount point from previous run..."
        try {
            Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction Stop
        }
        catch {
            dism /Unmount-Wim /MountDir:$mountPath /Discard 2>$null
        }
        Remove-Item -Path "$mountPath\*" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Handle ISO vs folder
    $sourcePath = $ISOPath
    $isoMounted = $false
    $mountedDrive = $null

    if ($ISOPath -match "\.iso$" -and (Test-Path $ISOPath)) {
        Write-Log "Mounting ISO: $ISOPath"
        $mountResult = Mount-DiskImage -ImagePath $ISOPath -PassThru
        Start-Sleep -Seconds 2
        $mountedDrive = ($mountResult | Get-Volume).DriveLetter
        $sourcePath = "${mountedDrive}:\"
        $isoMounted = $true
        Write-Log "ISO mounted as drive $mountedDrive`:"
    }
    elseif (-not (Test-Path $ISOPath)) {
        throw "ISO file not found: $ISOPath"
    }

    # Find install.wim or install.esd
    $installWIM = Join-Path $sourcePath "sources\install.wim"
    $installESD = Join-Path $sourcePath "sources\install.esd"

    if (Test-Path $installWIM) {
        Write-Log "Found install.wim"
        $workingWIM = Join-Path $OutputPath "install.wim"
        Write-Log "Copying install.wim to working directory..."
        Copy-Item -Path $installWIM -Destination $workingWIM -Force

        Write-Log "Removing read-only attribute..."
        Set-ItemProperty -Path $workingWIM -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        & attrib -R `"$workingWIM`"

        if ((Get-Item $workingWIM).IsReadOnly) {
            throw "Could not remove read-only attribute from install.wim"
        }
        Write-Log "Read-only attribute removed" -Level "SUCCESS"

        $installWIM = $workingWIM
    }
    elseif (Test-Path $installESD) {
        Write-Log "Found install.esd - converting to install.wim..."
        $workingWIM = Join-Path $OutputPath "install.wim"

        $esdInfo = Get-WindowsImage -ImagePath $installESD
        Write-Log "Available images in ESD:"
        $esdInfo | ForEach-Object { Write-Log "  Index $($_.ImageIndex): $($_.ImageName)" }

        foreach ($image in $esdInfo) {
            Write-Log "Exporting index $($image.ImageIndex)..."
            Export-WindowsImage -SourceImagePath $installESD -SourceIndex $image.ImageIndex -DestinationImagePath $workingWIM -CompressionType Maximum
        }

        $installWIM = $workingWIM
    }
    else {
        throw "Neither install.wim nor install.esd found in $sourcePath\sources"
    }

    # Download drivers
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "Downloading WiFi drivers from HP"
    Write-Log "=========================================="

    $driverPaths = Get-WiFiDrivers -DownloadPath $DriverDownloadPath

    if ($driverPaths.Count -eq 0) {
        throw "No drivers downloaded - check network connection"
    }

    Write-Log ""
    Write-Log "Downloaded $($driverPaths.Count) driver packages"

    # Inject drivers into each image index
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "Injecting drivers into install.wim"
    Write-Log "=========================================="

    $wimInfo = Get-WindowsImage -ImagePath $installWIM

    if (-not $AllEditions) {
        Write-Log "Filtering editions: $($EditionsToInject -join ', ')"
        $wimInfo = $wimInfo | Where-Object {
            $imageName = $_.ImageName
            $EditionsToInject | ForEach-Object { $imageName -match $_ } | Where-Object { $_ -eq $true }
        }
        Write-Log "Found $($wimInfo.Count) matching editions"
    }

    foreach ($image in $wimInfo) {
        Write-Log ""
        Write-Log "Processing: $($image.ImageName) (Index $($image.ImageIndex))"

        if ($PSCmdlet.ShouldProcess($image.ImageName, "Inject drivers")) {
            try {
                Write-Log "  Mounting image..."
                Mount-WindowsImage -ImagePath $installWIM -Index $image.ImageIndex -Path $mountPath | Out-Null

                foreach ($driverFolder in $driverPaths) {
                    if (Test-Path $driverFolder) {
                        Write-Log "  Adding drivers from: $(Split-Path $driverFolder -Leaf)"
                        try {
                            $result = Add-WindowsDriver -Path $mountPath -Driver $driverFolder -Recurse -ForceUnsigned -ErrorAction SilentlyContinue
                            $addedCount = ($result | Measure-Object).Count
                            if ($addedCount -gt 0) {
                                Write-Log "    Added $addedCount drivers" -Level "SUCCESS"
                            }
                        }
                        catch {
                            Write-Log "    Warning: $_" -Level "WARNING"
                        }
                    }
                }

                Write-Log "  Saving changes..."
                Dismount-WindowsImage -Path $mountPath -Save | Out-Null
                Write-Log "  Completed index $($image.ImageIndex)" -Level "SUCCESS"
            }
            catch {
                Write-Log "  ERROR: $_" -Level "ERROR"
                Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction SilentlyContinue
            }
        }
    }

    # Cleanup
    if ($isoMounted) {
        Write-Log ""
        Write-Log "Unmounting ISO..."
        Dismount-DiskImage -ImagePath $ISOPath | Out-Null
    }

    # Final summary
    $finalWIM = Join-Path $OutputPath "install.wim"
    $wimSize = [math]::Round((Get-Item $finalWIM).Length / 1GB, 2)

    Write-Log ""
    Write-Log "=========================================="
    Write-Log "COMPLETE!" -Level "SUCCESS"
    Write-Log "=========================================="
    Write-Log ""
    Write-Log "Modified install.wim: $finalWIM"
    Write-Log "Size: $wimSize GB"
    Write-Log ""
    Write-Log "NEXT STEPS:"
    Write-Log "1. Copy to USB:"
    Write-Log "   copy `"$finalWIM`" E:\sources\install.wim"
    Write-Log ""
    Write-Log "2. Or create new USB with Rufus and replace install.wim"
    Write-Log "=========================================="
}
catch {
    Write-Log "CRITICAL ERROR: $_" -Level "ERROR"
    Write-Log $_.ScriptStackTrace -Level "ERROR"

    if (Test-Path $mountPath) {
        try { Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction SilentlyContinue } catch {}
        try { dism /Unmount-Wim /MountDir:$mountPath /Discard 2>$null } catch {}
    }

    if ($isoMounted -and $ISOPath) {
        try { Dismount-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue } catch {}
    }

    exit 1
}
#endregion
