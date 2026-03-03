<#
.SYNOPSIS
    Builds customized, debloated Windows 11 ISOs for organizational deployment.

.DESCRIPTION
    Creates streamlined Windows 11 ISOs for Intune/Autopilot deployment:
    - Removes bloatware at the ISO level (no post-install remediation needed)
    - Injects HP WiFi drivers for Autopilot enrollment
    - Applies registry tweaks (telemetry, ads, consumer features)
    - Includes autounattend.xml for OOBE skip
    - Produces a single-edition ISO or one combined multi-edition ISO

.PARAMETER SourceISO
    Path to the source Windows 11 ISO file.

.PARAMETER OutputFolder
    Folder where the customized ISOs will be saved.

.PARAMETER Edition
    Which edition to build: "Education", "Enterprise", or "Both"

.PARAMETER SkipDrivers
    Skip HP WiFi driver injection (for testing).

.PARAMETER SkipDebloat
    Skip app removal (for testing).

.EXAMPLE
    .\Build-ISO.ps1 -SourceISO "C:\ISOs\Win11_24H2.iso" -OutputFolder "C:\ISOs\Custom" -Edition Both

.EXAMPLE
    .\Build-ISO.ps1 -SourceISO "C:\ISOs\Win11_24H2.iso" -OutputFolder "C:\ISOs\Custom" -Edition Education

.NOTES
    Author: robwol
    Version: 2.0
    Requirements: Windows ADK (DISM), Administrator privileges, ~40GB free space
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceISO,

    [Parameter(Mandatory = $true)]
    [string]$OutputFolder,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Education", "Enterprise", "Both")]
    [string]$Edition = "Both",

    [switch]$SkipDrivers,
    [switch]$SkipDebloat,

    [string]$LogPath = "C:\ISO-Build-Logs\Build-ISO.log"
)

#region ============== CONFIGURATION - EDIT THESE SECTIONS ==============

# ------------------------------------------------------------------------------
# EDITION CONFIGURATION
# NOTE: ImageIndex values vary by ISO. To find correct indexes for your ISO:
#   Mount-DiskImage -ImagePath "C:\Path\To\ISO.iso"
#   dism /Get-WimInfo /WimFile:"F:\sources\install.wim"
# ------------------------------------------------------------------------------
$EditionsConfig = @{
    "Education" = @{
        ImageIndex       = 1
        ProductKey       = "NW6C2-QMPVW-D7KKK-3GKT6-VCFB2"
        AutounattendFile = "autounattend-education-oobe.xml"
        OutputName       = "Windows11-Education-Custom.iso"
    }
    "Enterprise" = @{
        ImageIndex       = 3
        ProductKey       = "NPPR9-FWDCX-D2C8J-H872K-2YT43"
        AutounattendFile = "autounattend-enterprise-oobe.xml"
        OutputName       = "Windows11-Enterprise-Custom.iso"
    }
}

$MultiEditionOutputName = "Windows11-Education-Enterprise-Custom.iso"

# ------------------------------------------------------------------------------
# APPS TO REMOVE - Comment out any app you want to KEEP
# ------------------------------------------------------------------------------


# MICROSOFT APPS TO REMOVE
# Must match Config-AppList.ps1 and Remove-Bloatware.ps1

$MicrosoftAppsToRemove = @(
    # --- Bing & News ---
    "Microsoft.BingFinance"
    "Microsoft.BingFoodAndDrink"
    "Microsoft.BingHealthAndFitness"
    "Microsoft.BingNews"
    "Microsoft.BingSports"
    "Microsoft.BingTranslator"
    "Microsoft.BingTravel"
    "Microsoft.BingWeather"
    "Microsoft.BingSearch"
    "Microsoft.News"

    # --- Productivity Bloat ---
    "Clipchamp.Clipchamp"
    "Microsoft.549981C3F5F10"                # Cortana
    "Microsoft.Getstarted"                   # Tips
    #"Microsoft.Microsoft3DViewer"
    "Microsoft.MicrosoftJournal"
    "Microsoft.MicrosoftOfficeHub"
    "Microsoft.MicrosoftSolitaireCollection"
    #"Microsoft.MicrosoftStickyNotes"
    #"Microsoft.MixedReality.Portal"
    "Microsoft.NetworkSpeedTest"
    "Microsoft.Office.OneNote"               # UWP OneNote (not desktop)
    "Microsoft.Office.Sway"
    "Microsoft.OneConnect"
    #"Microsoft.Print3D"
    "Microsoft.SkypeApp"
    #"Microsoft.Todos"
    #"Microsoft.PowerAutomateDesktop"
    #"Microsoft.OutlookForWindows"            # New Outlook (if using classic)

    # --- Communication ---
    "Microsoft.People"
    "Microsoft.YourPhone"                    # Phone Link
    "Microsoft.WindowsCommunicationsapps"    # Mail & Calendar

    # --- System Bloat ---
    "Microsoft.Windows.DevHome"
    "Microsoft.WindowsAlarms"
    "Microsoft.WindowsFeedbackHub"
    "Microsoft.WindowsMaps"
    "Microsoft.WindowsSoundRecorder"
    "Microsoft.ZuneVideo"                    # Movies & TV
    "Microsoft.ZuneMusic"                    # Groove Music
    "Microsoft.GetHelp"
    "MicrosoftCorporationII.MicrosoftFamily"
    "MicrosoftCorporationII.QuickAssist"
    "MicrosoftWindows.CrossDevice"
    #"Microsoft.Windows.PeopleExperienceHost" # cannot remove (0x80070032)
    #"Windows.CBSPreview" # It is a core component tied to Microsoft.Windows.Client.CBS (Cloud Experience Host), which manages UI elements like the Start menu and search

    # --- Teams Personal (NOT Work Teams) ---
    "MicrosoftTeams"                         # Personal Teams from Store

    # --- Windows Copilot (Consumer - NOT M365 Copilot) ---
    "Microsoft.Copilot"
    "Microsoft.Windows.Ai.Copilot.Provider"
    "Microsoft.CopilotRuntime"

    # --- Xbox (ALL) ---
    "Microsoft.GamingApp"
    "Microsoft.XboxApp"
    "Microsoft.XboxGameOverlay"
    "Microsoft.XboxGamingOverlay"
    "Microsoft.XboxSpeechToTextOverlay"
    "Microsoft.Xbox.TCUI"
    "Microsoft.XboxIdentityProvider"
    #"Microsoft.XboxGameCallableUI" cannot remove (0x80070032)
    
    # --- KEEP THESE (Commented out) ---
    # "Microsoft.WindowsCalculator"
    # "Microsoft.WindowsCamera"
    # "Microsoft.ScreenSketch"
    # "Microsoft.Windows.Photos"
    # "Microsoft.WindowsStore"
    # "Microsoft.WindowsTerminal"
    # "Microsoft.WindowsNotepad"
    # "Microsoft.Paint"
    # "Microsoft.SecHealthUI"
    # "Microsoft.OneDriveSync"               # OneDrive - WE KEEP
    # "Microsoft.MicrosoftEdge*"             # Edge - WE KEEP
    # "MSTeams"                              # Work Teams - WE KEEP (NOT MicrosoftTeams)
)


# THIRD-PARTY APPS TO REMOVE
# Must match Config-AppList.ps1 and Remove-Bloatware.ps1

$ThirdPartyAppsToRemove = @(
    # --- Entertainment ---
    "Netflix"
    "Spotify"
    "Disney"
    "Amazon.com.Amazon"
    "AmazonVideo.PrimeVideo"
    "HULULLC.HULUPLUS"
    "SlingTV"
    "iHeartRadio"
    "TuneInRadio"
    "PandoraMediaInc"
    "Plex"

    # --- Social Media ---
    "Facebook"
    "Instagram"
    "Twitter"
    "TikTok"
    "Viber"
    "LinkedInforWindows"
    "XING"

    # --- Games ---
    "king.com.BubbleWitch3Saga"
    "king.com.CandyCrushSaga"
    "king.com.CandyCrushSodaSaga"
    "CaesarsSlotsFreeCasino"
    "DisneyMagicKingdoms"
    "FarmVille2CountryEscape"
    "HiddenCity"
    "MarchofEmpires"
    "RoyalRevolt"
    "Asphalt8Airborne"
    "COOKINGFEVER"

    # --- Utilities/Other ---
    "ACGMediaPlayer"
    "ActiproSoftwareLLC"
    "AdobeSystemsIncorporated.AdobePhotoshopExpress"
    "AutodeskSketchBook"
    "CyberLinkMediaSuiteEssentials"
    "DrawboardPDF"
    "Duolingo-LearnLanguagesforFree"
    "EclipseManager"
    "fitbit"
    "Flipboard"
    "NYTCrossword"
    "OneCalendar"
    "PhototasticCollage"
    "PicsArt-PhotoStudio"
    "PolarrPhotoEditorAcademicEdition"
    "Shazam"
    "Sidia.LiveWallpaper"
    "WinZipUniversal"
    "Wunderlist"
)


# OEM APPS TO REMOVE
# Must match Config-AppList.ps1 and Remove-Bloatware.ps1


# HP OEM Bloatware
$HPAppsToRemove = @(
    "AD2F1837.HPAIExperienceCenter"
    "AD2F1837.HPConnectedMusic"
    "AD2F1837.HPConnectedPhotopoweredbySnapfish"
    "AD2F1837.HPDesktopSupportUtilities"
    "AD2F1837.HPEasyClean"
    "AD2F1837.HPFileViewer"
    "AD2F1837.HPJumpStarts"
    "AD2F1837.HPPCHardwareDiagnosticsWindows"
    "AD2F1837.HPPowerManager"
    "AD2F1837.HPPrinterControl"
    "AD2F1837.HPPrivacySettings"
    "AD2F1837.HPQuickDrop"
    "AD2F1837.HPQuickTouch"
    "AD2F1837.HPRegistration"
    "AD2F1837.HPSupportAssistant"
    "AD2F1837.HPSureShieldAI"
    "AD2F1837.HPSystemInformation"
    "AD2F1837.HPWelcome"
    "AD2F1837.HPWorkWell"
    "AD2F1837.myHP"
)

# Dell OEM Bloatware
$DellAppsToRemove = @(
    "DellInc.DellCommandUpdate"
    "DellInc.DellDigitalDelivery"
    "DellInc.DellOptimizer"
    "DellInc.DellPowerManager"
    "DellInc.DellSupportAssistantforPCs"
    "DellInc.MyDell"
    "DellInc.PartnerPromo"
)

# Lenovo OEM Bloatware
$LenovoAppsToRemove = @(
    "E046963F.LenovoCompanion"
    "E046963F.LenovoSettings"
    "E0469640.LenovoUtility"
    "LenovoCorporation.LenovoID"
    "LenovoCorporation.LenovoSettings"
)

# ------------------------------------------------------------------------------
# HP DRIVER SOURCES - WiFi + Touchpad + Audio (verified working March 2026)
# ------------------------------------------------------------------------------
$HPDriverSources = @(
    # --- WiFi Drivers (verified working) ---
    @{
        Name     = "Realtek RTL8852/8822/8821 WiFi"
        URL      = "https://ftp.hp.com/pub/softpaq/sp155001-155500/sp155482.exe"
        Folder   = "Realtek_WiFi"
        Editions = @("Education", "Enterprise")
    },
    @{
        Name     = "Intel Wi-Fi 6E AX211/AX201/AX200"
        URL      = "https://ftp.hp.com/pub/softpaq/sp138501-139000/sp138607.exe"
        Folder   = "Intel_WiFi"
        Editions = @("Education", "Enterprise")
    },

    # --- Touchpad Drivers (verified working) ---
    @{
        Name     = "Synaptics/ELAN Precision Touchpad"
        URL      = "https://ftp.hp.com/pub/softpaq/sp139001-139500/sp139125.exe"
        Folder   = "Synaptics_ELAN_Touchpad"
        Editions = @("Education", "Enterprise")
    },
    @{
        Name     = "ELAN Precision Touchpad Filter"
        URL      = "https://ftp.hp.com/pub/softpaq/sp134001-134500/sp134374.exe"
        Folder   = "ELAN_Touchpad"
        Editions = @("Education", "Enterprise")
    },

    # --- Audio Drivers (verified working) ---
    @{
        Name     = "Realtek Audio (G11 models)"
        URL      = "https://ftp.hp.com/pub/softpaq/sp157001-157500/sp157064.exe"
        Folder   = "Realtek_Audio_G11"
        Editions = @("Education", "Enterprise")
    },
    @{
        Name     = "Realtek HD Audio (G5/G6 models)"
        URL      = "https://ftp.hp.com/pub/softpaq/sp154001-154500/sp154106.exe"
        Folder   = "Realtek_Audio_G5G6"
        Editions = @("Education", "Enterprise")
    }
)

# ------------------------------------------------------------------------------
# REGISTRY TWEAKS (Applied to offline image)
# ------------------------------------------------------------------------------
$RegistryTweaks = @{
    # Disable telemetry
    "Telemetry" = @(
        @{ Path = "SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "DoNotShowFeedbackNotifications"; Value = 1; Type = "DWord" }
        @{ Path = "SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 1; Type = "DWord" }
        @{ Path = "SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"; Name = "DisabledByGroupPolicy"; Value = 1; Type = "DWord" }
    )

    # Disable Widgets/News
    "Widgets" = @(
        @{ Path = "SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests"; Name = "value"; Value = 0; Type = "DWord" }
    )

    # Disable Windows Copilot (Consumer)
    "Copilot" = @(
        @{ Path = "SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1; Type = "DWord" }
    )

    # Disable Bing in Search
    "BingSearch" = @(
        @{ Path = "SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Value = 1; Type = "DWord" }
        @{ Path = "SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "ConnectedSearchUseWeb"; Value = 0; Type = "DWord" }
    )

    # Disable suggested apps and ads
    "ContentDelivery" = @(
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "ContentDeliveryAllowed"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "OemPreInstalledAppsEnabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "PreInstalledAppsEnabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "PreInstalledAppsEverEnabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SilentInstalledAppsEnabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SoftLandingEnabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContentEnabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338387Enabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338388Enabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338389Enabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338393Enabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-353694Enabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-353696Enabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-353698Enabled"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SystemPaneSuggestionsEnabled"; Value = 0; Type = "DWord" }
    )

    # Disable activity history
    "ActivityHistory" = @(
        @{ Path = "SOFTWARE\Policies\Microsoft\Windows\System"; Name = "EnableActivityFeed"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Policies\Microsoft\Windows\System"; Name = "PublishUserActivities"; Value = 0; Type = "DWord" }
        @{ Path = "SOFTWARE\Policies\Microsoft\Windows\System"; Name = "UploadUserActivities"; Value = 0; Type = "DWord" }
    )
}

# ------------------------------------------------------------------------------
# LOCALE SETTINGS (Norwegian)
# ------------------------------------------------------------------------------
$LocaleSettings = @{
    UILanguage   = "nb-NO"
    InputLocale  = "0414:00000414"
    SystemLocale = "nb-NO"
    UserLocale   = "nb-NO"
    TimeZone     = "W. Europe Standard Time"
    GeoID        = "177"  # Norway
}

#endregion ============== END CONFIGURATION ==============


#region ============== FUNCTIONS ==============

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Ensure log directory exists
    $logDir = Split-Path -Parent $LogPath
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue

    switch ($Level) {
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
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
        Write-Log "  Download failed: $_" -Level "WARNING"

        # Fallback: curl.exe
        try {
            & curl.exe -L -o $OutputPath $Url 2>&1 | Out-Null
            if (Test-Path $OutputPath) {
                $size = [math]::Round((Get-Item $OutputPath).Length / 1MB, 2)
                Write-Log "  Downloaded via curl: $size MB" -Level "SUCCESS"
                return $true
            }
        }
        catch {
            Write-Log "  Curl failed: $_" -Level "ERROR"
        }
    }
    return $false
}

function Get-Oscdimg {
    param([string]$DownloadPath)

    $oscdimgPath = Join-Path $DownloadPath "oscdimg.exe"

    # Check if already exists in working directory
    if (Test-Path $oscdimgPath) {
        Write-Log "Using existing oscdimg.exe"
        return $oscdimgPath
    }

    # Check Windows ADK locations
    $adkPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    )

    foreach ($path in $adkPaths) {
        if (Test-Path $path) {
            Write-Log "Found oscdimg in ADK: $path"
            return $path
        }
    }

    # ADK not installed - download and install Deployment Tools only
    Write-Log "Windows ADK not found. Installing Deployment Tools..."
    $adkSetupPath = Join-Path $DownloadPath "adksetup.exe"
    $adkUrl = "https://go.microsoft.com/fwlink/?linkid=2271337"

    if (Download-File -Url $adkUrl -OutputPath $adkSetupPath -Description "Windows ADK Setup") {
        Write-Log "Installing ADK Deployment Tools (this may take a few minutes)..."

        # Install only the Deployment Tools feature silently
        $installArgs = "/quiet /norestart /features OptionId.DeploymentTools"
        $process = Start-Process -FilePath $adkSetupPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            Write-Log "ADK Deployment Tools installed" -Level "SUCCESS"

            # Check ADK paths again
            foreach ($path in $adkPaths) {
                if (Test-Path $path) {
                    Write-Log "Found oscdimg.exe: $path"
                    return $path
                }
            }
        }
        elseif ($process.ExitCode -eq 3010) {
            # 3010 = Success, reboot required (but we can continue)
            Write-Log "ADK installed (reboot recommended later)" -Level "WARNING"

            foreach ($path in $adkPaths) {
                if (Test-Path $path) {
                    Write-Log "Found oscdimg.exe: $path"
                    return $path
                }
            }
        }
        else {
            Write-Log "ADK installation failed with exit code: $($process.ExitCode)" -Level "ERROR"
        }
    }

    # If we get here, installation failed
    Write-Log "=" * 60 -Level "ERROR"
    Write-Log "MANUAL INSTALLATION REQUIRED" -Level "ERROR"
    Write-Log "=" * 60 -Level "ERROR"
    Write-Log "Please install Windows ADK manually:" -Level "ERROR"
    Write-Log "1. Download: https://go.microsoft.com/fwlink/?linkid=2271337" -Level "ERROR"
    Write-Log "2. Run adksetup.exe" -Level "ERROR"
    Write-Log "3. Select 'Deployment Tools' feature only" -Level "ERROR"
    Write-Log "4. Re-run this script" -Level "ERROR"
    Write-Log "=" * 60 -Level "ERROR"

    throw "Could not obtain oscdimg.exe - Windows ADK installation required"
}

function Get-HPDrivers {
    param(
        [string]$DownloadPath,
        [string]$Edition = $null  # Optional: filter by edition
    )

    $driverPath = Join-Path $DownloadPath "HPDrivers"
    if (-not (Test-Path $driverPath)) {
        New-Item -Path $driverPath -ItemType Directory -Force | Out-Null
    }

    $downloadedPaths = @()

    foreach ($driver in $HPDriverSources) {
        # Filter by edition if specified
        if ($Edition -and $driver.Editions -and ($driver.Editions -notcontains $Edition)) {
            Write-Log "Skipping $($driver.Name) - not for $Edition edition"
            continue
        }

        $softpaqFile = Join-Path $DownloadPath "$($driver.Folder).exe"
        $extractPath = Join-Path $driverPath $driver.Folder

        # Skip if already extracted
        if (Test-Path $extractPath) {
            $existingInf = Get-ChildItem -Path $extractPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
            if ($existingInf.Count -gt 0) {
                Write-Log "Using existing drivers: $($driver.Name)"
                $downloadedPaths += $extractPath
                continue
            }
        }

        if (Download-File -Url $driver.URL -OutputPath $softpaqFile -Description $driver.Name) {
            # Validate downloaded file is not empty/corrupt
            $fileSize = (Get-Item $softpaqFile -ErrorAction SilentlyContinue).Length
            if ($fileSize -lt 100000) {  # Less than 100KB is likely corrupt
                Write-Log "  Downloaded file too small ($fileSize bytes) - skipping" -Level "WARNING"
                Remove-Item -Path $softpaqFile -Force -ErrorAction SilentlyContinue
                continue
            }

            Write-Log "Extracting: $($driver.Name)"

            if (-not (Test-Path $extractPath)) {
                New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
            }

            # HP Softpaqs are self-extracting
            try {
                Start-Process -FilePath $softpaqFile -ArgumentList "-e", "-f`"$extractPath`"", "-s" -Wait -NoNewWindow -ErrorAction Stop
            }
            catch {
                Write-Log "  Extraction failed: $_" -Level "WARNING"
                Remove-Item -Path $softpaqFile -Force -ErrorAction SilentlyContinue
                continue
            }

            $infFiles = Get-ChildItem -Path $extractPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
            if ($infFiles.Count -gt 0) {
                Write-Log "  Found $($infFiles.Count) driver files" -Level "SUCCESS"
                $downloadedPaths += $extractPath
            }

            Remove-Item -Path $softpaqFile -Force -ErrorAction SilentlyContinue
        }
    }

    return $downloadedPaths
}

function Remove-AppxFromImage {
    param(
        [string]$MountPath,
        [string[]]$AppList
    )

    Write-Log "Getting provisioned packages..."
    $provisionedPackages = Get-ProvisionedAppxPackage -Path $MountPath -ErrorAction SilentlyContinue

    $removed = 0
    $notFound = 0

    foreach ($app in $AppList) {
        $matchingPackages = $provisionedPackages | Where-Object { $_.DisplayName -like "*$app*" }

        if ($matchingPackages) {
            foreach ($package in $matchingPackages) {
                try {
                    Write-Log "  Removing: $($package.DisplayName)"
                    Remove-ProvisionedAppxPackage -Path $MountPath -PackageName $package.PackageName -ErrorAction Stop | Out-Null
                    $removed++
                }
                catch {
                    Write-Log "  Failed to remove $($package.DisplayName): $_" -Level "WARNING"
                }
            }
        }
        else {
            $notFound++
        }
    }

    Write-Log "Removed $removed packages, $notFound not found in image" -Level "SUCCESS"
}

function Set-OfflineRegistryTweaks {
    param(
        [string]$MountPath,
        [hashtable]$Tweaks
    )

    $softwareHive = Join-Path $MountPath "Windows\System32\config\SOFTWARE"
    $defaultHive = Join-Path $MountPath "Windows\System32\config\default"

    if (-not (Test-Path $softwareHive)) {
        Write-Log "SOFTWARE hive not found at $softwareHive" -Level "ERROR"
        return
    }

    # Load hives
    Write-Log "Loading registry hives..."
    reg load "HKLM\OFFLINE_SOFTWARE" $softwareHive 2>&1 | Out-Null
    reg load "HKLM\OFFLINE_DEFAULT" $defaultHive 2>&1 | Out-Null

    Start-Sleep -Seconds 2

    try {
        foreach ($category in $Tweaks.Keys) {
            Write-Log "  Applying: $category"

            foreach ($tweak in $Tweaks[$category]) {
                $fullPath = "HKLM:\OFFLINE_SOFTWARE\$($tweak.Path)"

                try {
                    if (-not (Test-Path $fullPath)) {
                        New-Item -Path $fullPath -Force | Out-Null
                    }
                    Set-ItemProperty -Path $fullPath -Name $tweak.Name -Value $tweak.Value -Type $tweak.Type -Force
                }
                catch {
                    Write-Log "    Failed: $($tweak.Path)\$($tweak.Name) - $_" -Level "WARNING"
                }
            }
        }
        Write-Log "Registry tweaks applied" -Level "SUCCESS"
    }
    finally {
        # Unload hives
        [gc]::Collect()
        Start-Sleep -Seconds 2
        reg unload "HKLM\OFFLINE_SOFTWARE" 2>&1 | Out-Null
        reg unload "HKLM\OFFLINE_DEFAULT" 2>&1 | Out-Null
    }
}

function New-AutounattendXml {
    param(
        [string]$OutputPath,
        [string]$EditionName,
        [int]$ImageIndex = 1,
        [string]$ProductKey = "",
        [hashtable]$Locale
    )

    $installFromSection = if ($ImageIndex -gt 0) {
@"
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/INDEX</Key>
                            <Value>$ImageIndex</Value>
                        </MetaData>
                    </InstallFrom>
"@
    }
    else {
@"
                    <!-- InstallFrom intentionally omitted to allow edition selection -->
"@
    }

    $productKeySection = if ($ProductKey -and $ProductKey.Trim()) {
@"
                <ProductKey>
                    <Key>$ProductKey</Key>
                    <WillShowUI>OnError</WillShowUI>
                </ProductKey>
"@
    }
    else {
@"
                <!-- Product key intentionally omitted -->
"@
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">

    <!-- ============================================================ -->
    <!-- Windows PE Pass: Language, Edition Selection, Disk Config    -->
    <!-- ============================================================ -->
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SetupUILanguage>
                <UILanguage>$($Locale.UILanguage)</UILanguage>
                <WillShowUI>OnError</WillShowUI>
            </SetupUILanguage>
            <InputLocale>$($Locale.InputLocale)</InputLocale>
            <SystemLocale>$($Locale.SystemLocale)</SystemLocale>
            <UILanguage>$($Locale.UILanguage)</UILanguage>
            <UserLocale>$($Locale.UserLocale)</UserLocale>
        </component>

        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">

            <!-- Auto-select Windows Edition -->
            <ImageInstall>
                <OSImage>
$installFromSection
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>3</PartitionID>
                    </InstallTo>
                </OSImage>
            </ImageInstall>

            <!-- Auto-partition disk (UEFI/GPT) -->
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <!-- EFI System Partition -->
                        <CreatePartition wcm:action="add">
                            <Order>1</Order>
                            <Size>300</Size>
                            <Type>EFI</Type>
                        </CreatePartition>
                        <!-- MSR Partition -->
                        <CreatePartition wcm:action="add">
                            <Order>2</Order>
                            <Size>128</Size>
                            <Type>MSR</Type>
                        </CreatePartition>
                        <!-- Windows Partition -->
                        <CreatePartition wcm:action="add">
                            <Order>3</Order>
                            <Extend>true</Extend>
                            <Type>Primary</Type>
                        </CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add">
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Format>FAT32</Format>
                            <Label>System</Label>
                        </ModifyPartition>
                        <ModifyPartition wcm:action="add">
                            <Order>2</Order>
                            <PartitionID>2</PartitionID>
                        </ModifyPartition>
                        <ModifyPartition wcm:action="add">
                            <Order>3</Order>
                            <PartitionID>3</PartitionID>
                            <Format>NTFS</Format>
                            <Label>Windows</Label>
                        </ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>

            <!-- Accept EULA, optional product key -->
            <UserData>
$productKeySection
                <AcceptEula>true</AcceptEula>
            </UserData>
        </component>
    </settings>

    <!-- ============================================================ -->
    <!-- Specialize Pass: Computer settings                           -->
    <!-- ============================================================ -->
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <TimeZone>$($Locale.TimeZone)</TimeZone>
            <!-- Let Autopilot handle computer name -->
        </component>

        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>$($Locale.InputLocale)</InputLocale>
            <SystemLocale>$($Locale.SystemLocale)</SystemLocale>
            <UILanguage>$($Locale.UILanguage)</UILanguage>
            <UserLocale>$($Locale.UserLocale)</UserLocale>
        </component>

        <!-- Disable Windows Copilot via registry -->
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f</Path>
                    <Description>Disable Windows Copilot</Description>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f</Path>
                    <Description>Disable Widgets</Description>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
    </settings>

    <!-- ============================================================ -->
    <!-- OOBE Pass: Skip pre-enrollment screens, preserve Autopilot  -->
    <!-- ============================================================ -->
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <!-- Keep WiFi + account/enrollment flow visible -->
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>false</HideOnlineAccountScreens>
                <HideLocalAccountScreen>false</HideLocalAccountScreen>
                <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
                <UnattendEnableRetailDemo>false</UnattendEnableRetailDemo>
                <VMModeOptimizations>
                    <SkipNotifyUILanguageChange>true</SkipNotifyUILanguageChange>
                </VMModeOptimizations>
            </OOBE>

            <TimeZone>$($Locale.TimeZone)</TimeZone>

            <!-- First logon: Additional cleanup -->
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>powershell -NoProfile -Command "Get-AppxPackage -AllUsers *Microsoft.Copilot* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue"</CommandLine>
                    <Description>Remove Copilot if reinstalled</Description>
                    <RequiresUserInput>false</RequiresUserInput>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>

        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>$($Locale.InputLocale)</InputLocale>
            <SystemLocale>$($Locale.SystemLocale)</SystemLocale>
            <UILanguage>$($Locale.UILanguage)</UILanguage>
            <UserLocale>$($Locale.UserLocale)</UserLocale>
        </component>
    </settings>

</unattend>
"@

    $xml | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    Write-Log "Created autounattend: $OutputPath" -Level "SUCCESS"
}

function Build-CustomISO {
    param(
        [string]$EditionName,
        [hashtable]$EditionConfig = $null,
        [string]$SourceISO,
        [string]$WorkingDir,
        [string]$OutputFolder,
        [string[]]$DriverPaths = @(),
        [string]$OscdimgPath,
        [int[]]$SourceImageIndexes = @(),
        [int]$UnattendImageIndex = 1,
        [string]$OutputISOName = ""
    )

    if (-not $SourceImageIndexes -or $SourceImageIndexes.Count -eq 0) {
        if (-not $EditionConfig -or -not $EditionConfig.ContainsKey("ImageIndex")) {
            throw "No source image index specified for $EditionName"
        }
        $SourceImageIndexes = @([int]$EditionConfig.ImageIndex)
    }

    if ([string]::IsNullOrWhiteSpace($OutputISOName)) {
        if (-not $EditionConfig -or -not $EditionConfig.ContainsKey("OutputName")) {
            throw "No output ISO name specified for $EditionName"
        }
        $OutputISOName = [string]$EditionConfig.OutputName
    }

    if ($UnattendImageIndex -lt 0) {
        throw "Unattend image index must be 0 or higher"
    }
    if ($UnattendImageIndex -gt 0 -and $UnattendImageIndex -gt $SourceImageIndexes.Count) {
        throw "Unattend image index $UnattendImageIndex exceeds available image count $($SourceImageIndexes.Count)"
    }

    Write-Log "=========================================="
    Write-Log "Building ISO: $EditionName"
    Write-Log "=========================================="

    $isoMountDir = Join-Path $WorkingDir "ISO_Mount"
    $wimMountDir = Join-Path $WorkingDir "WIM_Mount"
    $isoWorkDir = Join-Path $WorkingDir "ISO_$EditionName"
    $wimWorkFile = Join-Path $WorkingDir "install_$EditionName.wim"

    # Clean per-edition working artifacts to avoid stale edition carry-over
    if (Test-Path $isoWorkDir) {
        Write-Log "Cleaning previous work directory for $EditionName..."
        Remove-Item -Path $isoWorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $wimWorkFile) {
        Write-Log "Removing stale working WIM for $EditionName..."
        Remove-Item -Path $wimWorkFile -Force -ErrorAction SilentlyContinue
    }

    # Create directories
    @($isoMountDir, $wimMountDir, $isoWorkDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }

    try {
        # Mount source ISO
        Write-Log "Mounting source ISO..."
        $mountResult = Mount-DiskImage -ImagePath $SourceISO -PassThru
        Start-Sleep -Seconds 3
        $driveLetter = ($mountResult | Get-Volume).DriveLetter
        $sourcePath = "${driveLetter}:\"
        Write-Log "  Mounted as drive $driveLetter`:"

        # Copy ISO contents
        Write-Log "Copying ISO contents..."
        robocopy "$sourcePath" "$isoWorkDir" /E /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
        Write-Log "  ISO contents copied" -Level "SUCCESS"

        # Unmount source ISO
        Dismount-DiskImage -ImagePath $SourceISO | Out-Null

        # Find install.wim or install.esd
        $installWim = Join-Path $isoWorkDir "sources\install.wim"
        $installEsd = Join-Path $isoWorkDir "sources\install.esd"
        $sourceInstallImage = $null

        if (Test-Path $installEsd) {
            $sourceInstallImage = $installEsd
            Write-Log "Using source image: install.esd"
        }
        elseif (Test-Path $installWim) {
            $sourceInstallImage = $installWim
            Write-Log "Using source image: install.wim"
        }
        else {
            throw "No install.wim or install.esd found"
        }

        Write-Log "Exporting source image index(es): $($SourceImageIndexes -join ', ')"

        $firstExport = $true
        foreach ($sourceIndex in $SourceImageIndexes) {
            Write-Log "  Exporting source index $sourceIndex..."

            if ($firstExport) {
                Export-WindowsImage -SourceImagePath $sourceInstallImage -SourceIndex $sourceIndex `
                    -DestinationImagePath $wimWorkFile -CompressionType Maximum | Out-Null
                $firstExport = $false
            }
            else {
                # Older DISM modules do not support -Append on Export-WindowsImage.
                # Use dism.exe directly, which appends when destination WIM already exists.
                $dismExportResult = & dism.exe /Export-Image /SourceImageFile:"$sourceInstallImage" `
                    /SourceIndex:$sourceIndex /DestinationImageFile:"$wimWorkFile" /Compress:max 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "DISM export failed for source index $sourceIndex. Output: $dismExportResult"
                }
            }
        }

        Remove-Item $sourceInstallImage -Force
        Write-Log "  Exported $($SourceImageIndexes.Count) image(s) to working WIM" -Level "SUCCESS"

        $allAppsToRemove = $MicrosoftAppsToRemove + $ThirdPartyAppsToRemove + $HPAppsToRemove + $DellAppsToRemove + $LenovoAppsToRemove

        for ($targetIndex = 1; $targetIndex -le $SourceImageIndexes.Count; $targetIndex++) {
            Write-Log ""
            Write-Log "--- Customizing image index $targetIndex of $($SourceImageIndexes.Count) ---"

            # Mount each image index and apply same customizations
            Mount-WindowsImage -ImagePath $wimWorkFile -Index $targetIndex -Path $wimMountDir | Out-Null
            Write-Log "  WIM index $targetIndex mounted" -Level "SUCCESS"

            # Remove bloatware
            if (-not $SkipDebloat) {
                Write-Log ""
                Write-Log "--- Removing bloatware ---"
                Remove-AppxFromImage -MountPath $wimMountDir -AppList $allAppsToRemove
            }

            # Apply registry tweaks
            Write-Log ""
            Write-Log "--- Applying registry tweaks ---"
            Set-OfflineRegistryTweaks -MountPath $wimMountDir -Tweaks $RegistryTweaks

            # Inject drivers
            if (-not $SkipDrivers -and $DriverPaths -and $DriverPaths.Count -gt 0) {
                Write-Log ""
                Write-Log "--- Injecting HP WiFi drivers ---"

                foreach ($driverFolder in $DriverPaths) {
                    if (Test-Path $driverFolder) {
                        Write-Log "  Adding: $(Split-Path $driverFolder -Leaf)"
                        try {
                            $result = Add-WindowsDriver -Path $wimMountDir -Driver $driverFolder -Recurse -ForceUnsigned -ErrorAction SilentlyContinue
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
            }

            # Unmount and save - with DISM fallback for reliability
            Write-Log ""
            Write-Log "Saving changes for image index $targetIndex (this may take several minutes)..."

            # Force garbage collection to release file handles
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            Start-Sleep -Seconds 5

            # Try PowerShell cmdlet first, fall back to DISM
            $dismountSuccess = $false
            try {
                Write-Log "  Attempting PowerShell dismount..."
                Dismount-WindowsImage -Path $wimMountDir -Save -ErrorAction Stop | Out-Null
                $dismountSuccess = $true
            }
            catch {
                Write-Log "  PowerShell dismount failed, trying DISM..." -Level "WARNING"

                # Use DISM directly with explicit path
                $dismResult = & dism.exe /Unmount-Wim /MountDir:"$wimMountDir" /Commit 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $dismountSuccess = $true
                }
                else {
                    Write-Log "  DISM output: $dismResult" -Level "ERROR"
                }
            }

            if (-not $dismountSuccess) {
                # Last resort: try discard and throw error
                Write-Log "  Attempting discard to recover..." -Level "WARNING"
                & dism.exe /Unmount-Wim /MountDir:"$wimMountDir" /Discard 2>&1 | Out-Null
                throw "Failed to save WIM changes for image index $targetIndex. The mount was discarded."
            }

            Write-Log "  Image index $targetIndex saved" -Level "SUCCESS"
        }

        # Move WIM to ISO sources
        $destinationInstallWim = Join-Path $isoWorkDir "sources\install.wim"
        if (Test-Path $destinationInstallWim) {
            Remove-Item $destinationInstallWim -Force
        }
        Move-Item -Path $wimWorkFile -Destination $destinationInstallWim -Force

        # Create autounattend.xml
        Write-Log ""
        Write-Log "--- Creating autounattend.xml ---"
        $autounattendPath = Join-Path $isoWorkDir "autounattend.xml"
        New-AutounattendXml -OutputPath $autounattendPath `
            -EditionName $EditionName `
            -ImageIndex $UnattendImageIndex `
            -ProductKey "" `
            -Locale $LocaleSettings

        # Create ISO with oscdimg
        Write-Log ""
        Write-Log "--- Creating final ISO ---"

        $outputISO = Join-Path $OutputFolder $OutputISOName
        $bootData = "2#p0,e,b`"$isoWorkDir\boot\etfsboot.com`"#pEF,e,b`"$isoWorkDir\efi\microsoft\boot\efisys.bin`""

        $oscdimgArgs = @(
            "-m"
            "-o"
            "-u2"
            "-udfver102"
            "-bootdata:$bootData"
            "`"$isoWorkDir`""
            "`"$outputISO`""
        )

        Write-Log "Running oscdimg..."
        $process = Start-Process -FilePath $OscdimgPath -ArgumentList $oscdimgArgs -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0 -and (Test-Path $outputISO)) {
            $isoSize = [math]::Round((Get-Item $outputISO).Length / 1GB, 2)
            Write-Log "ISO created: $outputISO ($isoSize GB)" -Level "SUCCESS"
        }
        else {
            throw "oscdimg failed with exit code: $($process.ExitCode)"
        }

        return $outputISO
    }
    finally {
        # Cleanup
        Write-Log "Cleaning up..."

        # Try to dismount if still mounted
        try { Dismount-WindowsImage -Path $wimMountDir -Discard -ErrorAction SilentlyContinue } catch {}
        try { Dismount-DiskImage -ImagePath $SourceISO -ErrorAction SilentlyContinue } catch {}

        # Remove working directories
        @($isoMountDir, $wimMountDir, $isoWorkDir) | ForEach-Object {
            if (Test-Path $_) {
                Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path $wimWorkFile) {
            Remove-Item -Path $wimWorkFile -Force -ErrorAction SilentlyContinue
        }
    }
}

#endregion ============== END FUNCTIONS ==============


#region ============== MAIN SCRIPT ==============

$ErrorActionPreference = "Stop"
$startTime = Get-Date

# Banner
Clear-Host
Write-Host @"
========================================
  Modum Kommune ISO Builder
  Windows 11 Debloat + Customize
========================================
"@ -ForegroundColor Cyan

# Check admin
if (-not (Test-AdminPrivileges)) {
    Write-Host "ERROR: Run this script as Administrator" -ForegroundColor Red
    exit 1
}

# Validate source ISO
if (-not (Test-Path $SourceISO)) {
    Write-Host "ERROR: Source ISO not found: $SourceISO" -ForegroundColor Red
    exit 1
}

# Create output folder
if (-not (Test-Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}

# Working directory
$workingDir = "C:\ISO-Build-Work"
$driversDir = "C:\ISO-Build-Drivers"

@($workingDir, $driversDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}

Write-Log "=========================================="
Write-Log "Modum Kommune ISO Builder - Started"
Write-Log "=========================================="
Write-Log "Source ISO: $SourceISO"
Write-Log "Output Folder: $OutputFolder"
Write-Log "Edition(s): $Edition"

try {
    # Get oscdimg
    Write-Log ""
    Write-Log "--- Preparing tools ---"
    $oscdimgPath = Get-Oscdimg -DownloadPath $workingDir

    # Build ISO(s)
    $createdISOs = @()

    if ($Edition -eq "Both") {
        Write-Log ""

        # Download drivers for both editions and deduplicate paths
        $driverPaths = @()
        if (-not $SkipDrivers) {
            Write-Log "--- Downloading HP WiFi drivers for Education + Enterprise ---"
            $eduDriverPaths = Get-HPDrivers -DownloadPath $driversDir -Edition "Education"
            $entDriverPaths = Get-HPDrivers -DownloadPath $driversDir -Edition "Enterprise"
            $driverPaths = @($eduDriverPaths + $entDriverPaths | Where-Object { $_ } | Sort-Object -Unique)
            Write-Log "Ready: $($driverPaths.Count) unique driver packages for multi-edition ISO"
        }

        $sourceIndexes = @(
            [int]$EditionsConfig["Education"].ImageIndex,
            [int]$EditionsConfig["Enterprise"].ImageIndex
        )

        $isoPath = Build-CustomISO `
            -EditionName "Education-Enterprise" `
            -EditionConfig $null `
            -SourceISO $SourceISO `
            -WorkingDir $workingDir `
            -OutputFolder $OutputFolder `
            -DriverPaths $driverPaths `
            -OscdimgPath $oscdimgPath `
            -SourceImageIndexes $sourceIndexes `
            -UnattendImageIndex 0 `
            -OutputISOName $MultiEditionOutputName

        $createdISOs += $isoPath
    }
    else {
        Write-Log ""

        # Download HP drivers for this specific edition
        $driverPaths = @()
        if (-not $SkipDrivers) {
            Write-Log "--- Downloading HP WiFi drivers for $Edition ---"
            $driverPaths = Get-HPDrivers -DownloadPath $driversDir -Edition $Edition
            Write-Log "Ready: $($driverPaths.Count) driver packages for $Edition"
        }

        $isoPath = Build-CustomISO `
            -EditionName $Edition `
            -EditionConfig $EditionsConfig[$Edition] `
            -SourceISO $SourceISO `
            -WorkingDir $workingDir `
            -OutputFolder $OutputFolder `
            -DriverPaths $driverPaths `
            -OscdimgPath $oscdimgPath `
            -SourceImageIndexes @([int]$EditionsConfig[$Edition].ImageIndex) `
            -UnattendImageIndex 1

        $createdISOs += $isoPath
    }

    # Summary
    $duration = (Get-Date) - $startTime

    Write-Log ""
    Write-Log "=========================================="
    Write-Log "BUILD COMPLETE!" -Level "SUCCESS"
    Write-Log "=========================================="
    Write-Log "Duration: $($duration.ToString('hh\:mm\:ss'))"
    Write-Log ""
    Write-Log "Created ISOs:"
    foreach ($iso in $createdISOs) {
        $size = [math]::Round((Get-Item $iso).Length / 1GB, 2)
        Write-Log "  - $iso ($size GB)"
    }
    Write-Log ""
    Write-Log "Next steps:"
    Write-Log "  1. Use Rufus or similar to create bootable USB"
    Write-Log "  2. Boot device from USB"
    Write-Log "  3. Windows installs automatically"
    Write-Log "  4. Connect to WiFi (drivers pre-installed)"
    Write-Log "  5. Autopilot enrollment begins"
    Write-Log "=========================================="
}
catch {
    Write-Log "CRITICAL ERROR: $_" -Level "ERROR"
    Write-Log $_.ScriptStackTrace -Level "ERROR"
    exit 1
}
finally {
    # Cleanup: Unmount any stuck mounts before deleting
    Write-Log ""
    Write-Log "--- Cleanup ---"

    # Dismount any mounted WIMs in work directory
    $wimMountPath = Join-Path $workingDir "WIM_Mount"
    if (Test-Path $wimMountPath) {
        Write-Log "Unmounting WIM (if mounted)..."
        try {
            Dismount-WindowsImage -Path $wimMountPath -Discard -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            & dism.exe /Unmount-Wim /MountDir:"$wimMountPath" /Discard 2>&1 | Out-Null
        }
    }

    # Dismount source ISO
    if ($SourceISO -and (Test-Path $SourceISO)) {
        Write-Log "Unmounting source ISO (if mounted)..."
        try {
            Dismount-DiskImage -ImagePath $SourceISO -ErrorAction SilentlyContinue | Out-Null
        }
        catch {}
    }

    # Run DISM cleanup for any orphaned mounts
    Write-Log "Running DISM cleanup..."
    & dism.exe /Cleanup-Wim 2>&1 | Out-Null

    # Force garbage collection to release handles
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Seconds 2

    # Delete working directory
    if (Test-Path $workingDir) {
        Write-Log "Deleting working directory..."
        try {
            Remove-Item -Path $workingDir -Recurse -Force -ErrorAction Stop
            Write-Log "Working directory cleaned up" -Level "SUCCESS"
        }
        catch {
            Write-Log "Could not delete $workingDir - delete manually after reboot" -Level "WARNING"
        }
    }
}

#endregion ============== END MAIN SCRIPT ==============
