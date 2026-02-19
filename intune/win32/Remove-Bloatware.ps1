<#
.SYNOPSIS
Removes bloatware and applies registry hardening.

.DESCRIPTION
Win32 App Install Script for Intune. Removes Microsoft, third-party,
and OEM bloatware apps. Removes provisioned packages to prevent reinstall.
Applies registry settings to disable Copilot, Widgets, telemetry, and ads.

.NOTES
Author: Eriteach
Version: 2.0
Intune Run Context: System
#>

param(
    [string]$LogPath = "$env:ProgramData\Intune\Logs\Remove-Bloatware.log"
)

$ErrorActionPreference = "Continue"
$script:RemovedApps = 0
$script:FailedApps = 0

# Logging
$logDir = Split-Path -Parent $LogPath
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
    Write-Host $logMessage
}

# Microsoft apps to remove
$MicrosoftApps = @(
    "Microsoft.BingFinance", "Microsoft.BingFoodAndDrink", "Microsoft.BingHealthAndFitness"
    "Microsoft.BingNews", "Microsoft.BingSports", "Microsoft.BingTranslator"
    "Microsoft.BingTravel", "Microsoft.BingWeather", "Microsoft.BingSearch", "Microsoft.News"
    "Clipchamp.Clipchamp", "Microsoft.549981C3F5F10", "Microsoft.Getstarted"
    "Microsoft.MicrosoftJournal", "Microsoft.MicrosoftOfficeHub", "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.NetworkSpeedTest", "Microsoft.Office.OneNote", "Microsoft.Office.Sway"
    "Microsoft.OneConnect", "Microsoft.SkypeApp", "Microsoft.People", "Microsoft.YourPhone"
    "Microsoft.WindowsCommunicationsapps", "Microsoft.Windows.DevHome", "Microsoft.WindowsAlarms"
    "Microsoft.WindowsFeedbackHub", "Microsoft.WindowsMaps", "Microsoft.WindowsSoundRecorder"
    "Microsoft.ZuneVideo", "Microsoft.ZuneMusic", "Microsoft.GetHelp"
    "MicrosoftCorporationII.MicrosoftFamily", "MicrosoftCorporationII.QuickAssist"
    "MicrosoftWindows.CrossDevice", "MicrosoftTeams"
    "Microsoft.Copilot", "Microsoft.Windows.Ai.Copilot.Provider", "Microsoft.CopilotRuntime"
    "Microsoft.GamingApp", "Microsoft.XboxApp", "Microsoft.XboxGameOverlay"
    "Microsoft.XboxGamingOverlay", "Microsoft.XboxSpeechToTextOverlay"
    "Microsoft.Xbox.TCUI", "Microsoft.XboxIdentityProvider"
)

# Third-party apps to remove
$ThirdPartyApps = @(
    "Netflix", "Spotify", "Disney", "Amazon.com.Amazon", "AmazonVideo.PrimeVideo"
    "HULULLC.HULUPLUS", "SlingTV", "iHeartRadio", "TuneInRadio", "PandoraMediaInc", "Plex"
    "Facebook", "Instagram", "Twitter", "TikTok", "Viber", "LinkedInforWindows", "XING"
    "king.com.BubbleWitch3Saga", "king.com.CandyCrushSaga", "king.com.CandyCrushSodaSaga"
    "CaesarsSlotsFreeCasino", "DisneyMagicKingdoms", "FarmVille2CountryEscape"
    "HiddenCity", "MarchofEmpires", "RoyalRevolt", "Asphalt8Airborne", "COOKINGFEVER"
    "ACGMediaPlayer", "ActiproSoftwareLLC", "AdobeSystemsIncorporated.AdobePhotoshopExpress"
    "AutodeskSketchBook", "CyberLinkMediaSuiteEssentials", "DrawboardPDF"
    "Duolingo-LearnLanguagesforFree", "EclipseManager", "fitbit", "Flipboard"
    "NYTCrossword", "OneCalendar", "PhototasticCollage", "PicsArt-PhotoStudio"
    "PolarrPhotoEditorAcademicEdition", "Shazam", "Sidia.LiveWallpaper", "WinZipUniversal", "Wunderlist"
)

# OEM apps to remove
$HPApps = @(
    "AD2F1837.HPAIExperienceCenter", "AD2F1837.HPConnectedMusic", "AD2F1837.HPConnectedPhotopoweredbySnapfish"
    "AD2F1837.HPDesktopSupportUtilities", "AD2F1837.HPEasyClean", "AD2F1837.HPFileViewer"
    "AD2F1837.HPJumpStarts", "AD2F1837.HPPCHardwareDiagnosticsWindows", "AD2F1837.HPPowerManager"
    "AD2F1837.HPPrinterControl", "AD2F1837.HPPrivacySettings", "AD2F1837.HPQuickDrop"
    "AD2F1837.HPQuickTouch", "AD2F1837.HPRegistration", "AD2F1837.HPSupportAssistant"
    "AD2F1837.HPSureShieldAI", "AD2F1837.HPSystemInformation", "AD2F1837.HPWelcome"
    "AD2F1837.HPWorkWell", "AD2F1837.myHP"
)

$DellApps = @(
    "DellInc.DellCommandUpdate", "DellInc.DellDigitalDelivery", "DellInc.DellOptimizer"
    "DellInc.DellPowerManager", "DellInc.DellSupportAssistantforPCs", "DellInc.MyDell", "DellInc.PartnerPromo"
)

$LenovoApps = @(
    "E046963F.LenovoCompanion", "E046963F.LenovoSettings", "E0469640.LenovoUtility"
    "LenovoCorporation.LenovoID", "LenovoCorporation.LenovoSettings"
)

# Registry settings
$RegistrySettings = @(
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1; Type = "DWord" }
    @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1; Type = "DWord" }
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowCopilotButton"; Value = 0; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 0; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests"; Name = "value"; Value = 0; Type = "DWord" }
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarDa"; Value = 0; Type = "DWord" }
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled"; Value = 0; Type = "DWord" }
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"; Name = "CortanaConsent"; Value = 0; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Value = 1; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "ConnectedSearchUseWeb"; Value = 0; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; Value = 0; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "DoNotShowFeedbackNotifications"; Value = 1; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"; Name = "AllowTelemetry"; Value = 0; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 1; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"; Name = "DisabledByGroupPolicy"; Value = 1; Type = "DWord" }
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "ContentDeliveryAllowed"; Value = 0; Type = "DWord" }
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "OemPreInstalledAppsEnabled"; Value = 0; Type = "DWord" }
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "PreInstalledAppsEnabled"; Value = 0; Type = "DWord" }
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SilentInstalledAppsEnabled"; Value = 0; Type = "DWord" }
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SystemPaneSuggestionsEnabled"; Value = 0; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "EnableActivityFeed"; Value = 0; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "PublishUserActivities"; Value = 0; Type = "DWord" }
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "UploadUserActivities"; Value = 0; Type = "DWord" }
)

function Remove-BloatwareApps {
    param([string[]]$AppList, [string]$Category)

    Write-Log "Removing $Category apps..."

    foreach ($app in $AppList) {
        $packages = Get-AppxPackage -Name "*$app*" -AllUsers -ErrorAction SilentlyContinue

        foreach ($package in $packages) {
            try {
                Write-Log "  Removing: $($package.Name)"
                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
                $script:RemovedApps++
            }
            catch {
                Write-Log "  Failed: $($package.Name) - $_" -Level "WARNING"
                $script:FailedApps++
            }
        }
    }
}

function Remove-ProvisionedApps {
    param([string[]]$AppList)

    Write-Log "Removing provisioned packages..."

    $provisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

    foreach ($app in $AppList) {
        $matchingPackages = $provisionedPackages | Where-Object { $_.DisplayName -like "*$app*" }

        foreach ($package in $matchingPackages) {
            try {
                Write-Log "  Removing provisioned: $($package.DisplayName)"
                Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Log "  Failed provisioned: $($package.DisplayName) - $_" -Level "WARNING"
            }
        }
    }
}

function Set-RegistrySettings {
    param([array]$Settings)

    Write-Log "Applying registry settings..."

    foreach ($setting in $Settings) {
        try {
            if (-not (Test-Path $setting.Path)) {
                New-Item -Path $setting.Path -Force | Out-Null
            }
            Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Force
        }
        catch {
            Write-Log "  Registry failed: $($setting.Path)\$($setting.Name) - $_" -Level "WARNING"
        }
    }

    Write-Log "Registry settings applied" -Level "SUCCESS"
}

# Main execution
Write-Log "========================================"
Write-Log "Bloatware Removal - Start"
Write-Log "========================================"
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)"
Write-Log "Build: $((Get-CimInstance Win32_OperatingSystem).BuildNumber)"

try {
    $AllApps = $MicrosoftApps + $ThirdPartyApps + $HPApps + $DellApps + $LenovoApps

    Write-Log ""
    Write-Log "--- Step 1: Removing installed AppX packages ---"
    Remove-BloatwareApps -AppList $MicrosoftApps -Category "Microsoft"
    Remove-BloatwareApps -AppList $ThirdPartyApps -Category "Third-party"
    Remove-BloatwareApps -AppList $HPApps -Category "HP OEM"
    Remove-BloatwareApps -AppList $DellApps -Category "Dell OEM"
    Remove-BloatwareApps -AppList $LenovoApps -Category "Lenovo OEM"

    Write-Log ""
    Write-Log "--- Step 2: Removing provisioned packages ---"
    Remove-ProvisionedApps -AppList $AllApps

    Write-Log ""
    Write-Log "--- Step 3: Applying registry settings ---"
    Set-RegistrySettings -Settings $RegistrySettings

    Write-Log ""
    Write-Log "========================================"
    Write-Log "Bloatware Removal - Complete" -Level "SUCCESS"
    Write-Log "========================================"
    Write-Log "Apps removed: $($script:RemovedApps)"
    Write-Log "Apps failed: $($script:FailedApps)"

    exit 0
}
catch {
    Write-Log "Critical error: $_" -Level "ERROR"
    exit 1
}
