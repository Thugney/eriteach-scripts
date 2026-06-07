# ============================================================================
# Eriteach Scripts
# Author: Robel (https://github.com/Thugney)
# Repository: https://github.com/Thugney/eriteach-scripts
# License: MIT
# ============================================================================

<#
.SYNOPSIS
    Eksporterer installerte og brukte applikasjoner fra endepunkter til Excel.

.DESCRIPTION
    Uses Microsoft Graph interactive authentication to run Microsoft Defender XDR
    Advanced Hunting queries and optional Intune detected app collection. The
    workbook helps determine which applications are installed, which are actually
    executed by endpoints, and which applications need owner validation.

    Primary usage signal:
      - DeviceProcessEvents / ProcessCreated = application executed by endpoint

    Supporting inventory signals:
      - DeviceTvmSoftwareInventory = Defender TVM installed software inventory
      - Intune detectedApps = Intune discovered applications

    Recommended lookback is 45 days. This catches monthly or occasional business
    applications without making the report too stale. Use 30 days for stricter
    current usage or 90 days for initial broad discovery.

    Required delegated Graph scopes:
      - SecurityEvents.Read.All
      - DeviceManagementManagedDevices.Read.All when -IncludeIntuneDetectedApps is used

    Required modules:
      - Microsoft.Graph.Authentication
      - ImportExcel

.PARAMETER LookbackDays
    Number of days to evaluate process execution. Default is 45.

.PARAMETER OutputPath
    Full path for the Excel workbook. Defaults to C:\MK-LogFiles.

.PARAMETER IncludeIntuneDetectedApps
    Adds Intune detected apps to the workbook and merged control view.

.PARAMETER SkipDefenderInventory
    Skips DeviceTvmSoftwareInventory if TVM inventory is unavailable.

.PARAMETER IncludeMicrosoftSystemComponents
    Includes common Windows system binaries. By default these are filtered out.

.PARAMETER TopRows
    Maximum rows returned from each Defender Advanced Hunting query after aggregation.

.EXAMPLE
    .\Export-TenantEndpointAppUsage.ps1 -IncludeIntuneDetectedApps

.EXAMPLE
    .\Export-TenantEndpointAppUsage.ps1 -LookbackDays 30 -IncludeIntuneDetectedApps -OutputPath C:\MK-LogFiles\EndpointApps.xlsx

.NOTES
    Author: Eriteach
    Version: 1.0
    Run Context: Interactive admin workstation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 180)]
    [int]$LookbackDays = 45,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path -Path 'C:\MK-LogFiles' -ChildPath ("EndpointAppUsage_{0}.xlsx" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))),

    [Parameter(Mandatory = $false)]
    [switch]$IncludeIntuneDetectedApps,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDefenderInventory,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeMicrosoftSystemComponents,

    [Parameter(Mandatory = $false)]
    [ValidateRange(100, 100000)]
    [int]$TopRows = 20000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logRoot = 'C:\MK-LogFiles'
$logPath = Join-Path -Path $logRoot -ChildPath ("{0}.log" -f $scriptName)

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    try {
        if (-not (Test-Path -Path $logRoot)) {
            New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $entry = "{0} [{1}] {2}" -f $timestamp, $Level, $Message
        $entry | Out-File -FilePath $logPath -Append -Encoding UTF8
        Write-Host $entry
    }
    catch {
        Write-Host ("Logging failed: {0}" -f $_.Exception.Message)
    }
}

function Ensure-Module {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)

    try {
        if (-not (Get-Module -ListAvailable -Name $Name)) {
            Write-Log -Message ("Installing missing module: {0}" -f $Name)
            Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
        }

        Import-Module -Name $Name -Force
        Write-Log -Message ("Loaded module: {0}" -f $Name)
    }
    catch {
        Write-Log -Message ("Failed to load module {0}: {1}" -f $Name, $_.Exception.Message) -Level ERROR
        throw
    }
}

function ConvertTo-SafeString {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ''
    }

    return ([string]$Value).Trim()
}

function Get-NormalizedAppKey {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][AllowNull()][string]$Name)

    $value = ConvertTo-SafeString -Value $Name
    if ([string]::IsNullOrWhiteSpace($value)) {
        return ''
    }

    $normalized = $value.ToLowerInvariant()
    $normalized = $normalized -replace '\(r\)|\(tm\)|®|™', ''
    $normalized = $normalized -replace '\b(x64|x86|64-bit|32-bit|en-us|nb-no|machine-wide installer)\b', ''
    $normalized = $normalized -replace '[^a-z0-9]+', ' '
    $normalized = $normalized -replace '\s+', ' '
    return $normalized.Trim()
}

function Invoke-AdvancedHuntingQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][string]$Name
    )

    try {
        Write-Log -Message ("Running Defender Advanced Hunting query: {0}" -f $Name)
        $body = @{ Query = $Query } | ConvertTo-Json -Depth 5
        $response = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/security/runHuntingQuery' -Body $body -ContentType 'application/json'
        $rows = @($response.results)
        Write-Log -Message ("Query completed: {0}. Rows: {1}" -f $Name, $rows.Count)
        return $rows
    }
    catch {
        Write-Log -Message ("Advanced Hunting query failed [{0}]: {1}" -f $Name, $_.Exception.Message) -Level ERROR
        throw
    }
}

function Invoke-GraphPagedRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Name
    )

    try {
        Write-Log -Message ("Running Graph paged request: {0}" -f $Name)
        $items = New-Object System.Collections.Generic.List[object]
        $nextLink = $Uri

        while (-not [string]::IsNullOrWhiteSpace($nextLink)) {
            $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink
            if ($response.value) {
                foreach ($item in $response.value) {
                    $items.Add($item)
                }
            }
            $nextLink = $response.'@odata.nextLink'
        }

        Write-Log -Message ("Graph request completed: {0}. Rows: {1}" -f $Name, $items.Count)
        return @($items)
    }
    catch {
        Write-Log -Message ("Graph request failed [{0}]: {1}" -f $Name, $_.Exception.Message) -Level ERROR
        throw
    }
}

function Get-DefenderInUseApplicationQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$Days,
        [Parameter(Mandatory = $true)][int]$Limit,
        [Parameter(Mandatory = $true)][bool]$IncludeSystemComponents
    )

    return @"
let Lookback = ${Days}d;
let IncludeSystemComponents = $($IncludeSystemComponents.ToString().ToLowerInvariant());
DeviceProcessEvents
| where Timestamp >= ago(Lookback)
| where ActionType == "ProcessCreated"
| where isnotempty(DeviceName) and isnotempty(FileName)
| extend ProductNameRaw = tostring(ProcessVersionInfoProductName)
| extend FileDescriptionRaw = tostring(ProcessVersionInfoFileDescription)
| extend PublisherRaw = tostring(ProcessVersionInfoCompanyName)
| extend AppName = case(isnotempty(ProductNameRaw), ProductNameRaw, isnotempty(FileDescriptionRaw), FileDescriptionRaw, FileName)
| extend Publisher = iff(isempty(PublisherRaw), "Unknown", PublisherRaw)
| extend AppKey = tolower(replace_regex(AppName, @"[^A-Za-z0-9]+", " "))
| where IncludeSystemComponents == true or not((Publisher has "Microsoft" or Publisher has "Windows") and FolderPath startswith @"C:\Windows\")
| where IncludeSystemComponents == true or not(FileName in~ ("svchost.exe", "dllhost.exe", "conhost.exe", "rundll32.exe", "regsvr32.exe", "backgroundtaskhost.exe", "runtimebroker.exe", "sihost.exe", "taskhostw.exe", "searchindexer.exe", "searchprotocolhost.exe", "searchfilterhost.exe", "fontdrvhost.exe", "audiodg.exe", "wermgr.exe", "werfault.exe"))
| summarize ExecutionCount = count(), DeviceCount = dcount(DeviceId), UserCount = dcount(AccountUpn), FirstSeen = min(Timestamp), LastSeen = max(Timestamp), ExampleDevices = make_set(DeviceName, 10), ExampleUsers = make_set(AccountUpn, 10), ExamplePaths = make_set(FolderPath, 10), FileNames = make_set(FileName, 20), SHA256s = make_set(SHA256, 20) by AppName, AppKey, Publisher
| extend Source = "Defender Process Execution"
| top $Limit by DeviceCount desc, ExecutionCount desc
"@
}

function Get-DefenderInstalledSoftwareQuery {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$Limit)

    return @"
DeviceTvmSoftwareInventory
| where isnotempty(DeviceName) and isnotempty(SoftwareName)
| extend AppName = SoftwareName
| extend Publisher = iff(isempty(SoftwareVendor), "Unknown", SoftwareVendor)
| extend AppKey = tolower(replace_regex(AppName, @"[^A-Za-z0-9]+", " "))
| summarize InstalledDeviceCount = dcount(DeviceId), InstalledVersions = make_set(SoftwareVersion, 30), ExampleDevices = make_set(DeviceName, 10), Platforms = make_set(OSPlatform, 10) by AppName, AppKey, Publisher
| extend Source = "Defender TVM Software Inventory"
| top $Limit by InstalledDeviceCount desc
"@
}

function Get-IntuneDetectedApps {
    [CmdletBinding()]
    param()

    $rawApps = Invoke-GraphPagedRequest -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/detectedApps?$top=999' -Name 'Intune detectedApps'
    $apps = foreach ($app in $rawApps) {
        [PSCustomObject]@{
            AppName = ConvertTo-SafeString -Value $app.displayName
            AppKey = Get-NormalizedAppKey -Name $app.displayName
            Publisher = ConvertTo-SafeString -Value $app.publisher
            Version = ConvertTo-SafeString -Value $app.version
            Platform = ConvertTo-SafeString -Value $app.platform
            InstalledDeviceCount = [int]($app.deviceCount)
            SizeInByte = $app.sizeInByte
            Source = 'Intune detectedApps'
        }
    }

    return @($apps | Where-Object { -not [string]::IsNullOrWhiteSpace($_.AppName) })
}

function Merge-AppControlView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object[]]$InUseApps,
        [Parameter(Mandatory = $false)][AllowNull()][object[]]$InstalledApps,
        [Parameter(Mandatory = $false)][AllowNull()][object[]]$IntuneApps
    )

    $map = @{}

    foreach ($row in @($InUseApps)) {
        $key = Get-NormalizedAppKey -Name $row.AppName
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if (-not $map.ContainsKey($key)) {
            $map[$key] = [ordered]@{ AppName = $row.AppName; Publisher = $row.Publisher; InUse = 'Yes'; DefenderExecutionCount = 0; DefenderUsedDeviceCount = 0; DefenderUserCount = 0; DefenderFirstSeen = $null; DefenderLastSeen = $null; DefenderInstalled = 'No'; DefenderInstalledDeviceCount = 0; IntuneDetected = 'No'; IntuneInstalledDeviceCount = 0; Sources = New-Object System.Collections.Generic.List[string]; RecommendedAction = 'Review'; AppKey = $key }
        }
        $map[$key].InUse = 'Yes'
        $map[$key].DefenderExecutionCount = [int64]$row.ExecutionCount
        $map[$key].DefenderUsedDeviceCount = [int]$row.DeviceCount
        $map[$key].DefenderUserCount = [int]$row.UserCount
        $map[$key].DefenderFirstSeen = $row.FirstSeen
        $map[$key].DefenderLastSeen = $row.LastSeen
        $map[$key].Sources.Add('Defender execution')
    }

    foreach ($row in @($InstalledApps)) {
        $key = Get-NormalizedAppKey -Name $row.AppName
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if (-not $map.ContainsKey($key)) {
            $map[$key] = [ordered]@{ AppName = $row.AppName; Publisher = $row.Publisher; InUse = 'No'; DefenderExecutionCount = 0; DefenderUsedDeviceCount = 0; DefenderUserCount = 0; DefenderFirstSeen = $null; DefenderLastSeen = $null; DefenderInstalled = 'Yes'; DefenderInstalledDeviceCount = 0; IntuneDetected = 'No'; IntuneInstalledDeviceCount = 0; Sources = New-Object System.Collections.Generic.List[string]; RecommendedAction = 'Review installed - no execution in lookback'; AppKey = $key }
        }
        $map[$key].DefenderInstalled = 'Yes'
        $map[$key].DefenderInstalledDeviceCount = [int]$row.InstalledDeviceCount
        if ([string]::IsNullOrWhiteSpace($map[$key].Publisher) -or $map[$key].Publisher -eq 'Unknown') { $map[$key].Publisher = $row.Publisher }
        $map[$key].Sources.Add('Defender inventory')
    }

    foreach ($row in @($IntuneApps)) {
        $key = Get-NormalizedAppKey -Name $row.AppName
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if (-not $map.ContainsKey($key)) {
            $map[$key] = [ordered]@{ AppName = $row.AppName; Publisher = $row.Publisher; InUse = 'No'; DefenderExecutionCount = 0; DefenderUsedDeviceCount = 0; DefenderUserCount = 0; DefenderFirstSeen = $null; DefenderLastSeen = $null; DefenderInstalled = 'No'; DefenderInstalledDeviceCount = 0; IntuneDetected = 'Yes'; IntuneInstalledDeviceCount = 0; Sources = New-Object System.Collections.Generic.List[string]; RecommendedAction = 'Review Intune detected app - no execution in lookback'; AppKey = $key }
        }
        $map[$key].IntuneDetected = 'Yes'
        $map[$key].IntuneInstalledDeviceCount += [int]$row.InstalledDeviceCount
        if ([string]::IsNullOrWhiteSpace($map[$key].Publisher) -or $map[$key].Publisher -eq 'Unknown') { $map[$key].Publisher = $row.Publisher }
        $map[$key].Sources.Add('Intune detectedApps')
    }

    $merged = foreach ($entry in $map.GetEnumerator()) {
        $item = $entry.Value
        if ($item.InUse -eq 'Yes' -and ($item.DefenderInstalled -eq 'Yes' -or $item.IntuneDetected -eq 'Yes')) { $item.RecommendedAction = 'Keep under control - installed and used' }
        elseif ($item.InUse -eq 'Yes') { $item.RecommendedAction = 'Investigate portable/user-scope app or missing inventory signal' }
        elseif ($item.DefenderInstalled -eq 'Yes' -or $item.IntuneDetected -eq 'Yes') { $item.RecommendedAction = 'Candidate for owner validation / removal if not approved' }

        [PSCustomObject]@{
            AppName = $item.AppName
            Publisher = $item.Publisher
            InUse = $item.InUse
            DefenderExecutionCount = $item.DefenderExecutionCount
            DefenderUsedDeviceCount = $item.DefenderUsedDeviceCount
            DefenderUserCount = $item.DefenderUserCount
            DefenderFirstSeen = $item.DefenderFirstSeen
            DefenderLastSeen = $item.DefenderLastSeen
            DefenderInstalled = $item.DefenderInstalled
            DefenderInstalledDeviceCount = $item.DefenderInstalledDeviceCount
            IntuneDetected = $item.IntuneDetected
            IntuneInstalledDeviceCount = $item.IntuneInstalledDeviceCount
            Sources = (($item.Sources | Select-Object -Unique) -join '; ')
            RecommendedAction = $item.RecommendedAction
            AppKey = $item.AppKey
        }
    }

    return @($merged | Sort-Object -Property @{ Expression = 'InUse'; Descending = $true }, @{ Expression = 'DefenderUsedDeviceCount'; Descending = $true }, @{ Expression = 'IntuneInstalledDeviceCount'; Descending = $true }, AppName)
}

function Export-WorksheetSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$WorksheetName,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][switch]$ClearSheet
    )

    try {
        if ($Rows.Count -eq 0) { $Rows = @([PSCustomObject]@{ Message = 'No rows returned' }) }
        $params = @{ Path = $Path; WorksheetName = $WorksheetName; AutoSize = $true; AutoFilter = $true; FreezeTopRow = $true; BoldTopRow = $true; TableName = ($WorksheetName -replace '[^A-Za-z0-9]', '') }
        if ($ClearSheet.IsPresent) { $params.ClearSheet = $true }
        $Rows | Export-Excel @params
        Write-Log -Message ("Exported worksheet {0}. Rows: {1}" -f $WorksheetName, $Rows.Count)
    }
    catch {
        Write-Log -Message ("Failed to export worksheet {0}: {1}" -f $WorksheetName, $_.Exception.Message) -Level ERROR
        throw
    }
}

try {
    Write-Log -Message 'Starting tenant endpoint application usage export.'

    if (-not (Test-Path -Path $logRoot)) { New-Item -Path $logRoot -ItemType Directory -Force | Out-Null }
    $outputDirectory = Split-Path -Path $OutputPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -Path $outputDirectory)) { New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null }

    Ensure-Module -Name 'Microsoft.Graph.Authentication'
    Ensure-Module -Name 'ImportExcel'

    $scopes = @('SecurityEvents.Read.All')
    if ($IncludeIntuneDetectedApps.IsPresent) { $scopes += 'DeviceManagementManagedDevices.Read.All' }

    Write-Log -Message ("Connecting to Microsoft Graph with scopes: {0}" -f ($scopes -join ', '))
    Connect-MgGraph -Scopes $scopes -NoWelcome
    $context = Get-MgContext
    if ($null -eq $context) { throw 'Microsoft Graph connection failed. No context returned.' }

    $inUseApps = @(Invoke-AdvancedHuntingQuery -Query (Get-DefenderInUseApplicationQuery -Days $LookbackDays -Limit $TopRows -IncludeSystemComponents $IncludeMicrosoftSystemComponents.IsPresent) -Name 'Defender in-use applications')
    $installedApps = @()
    if (-not $SkipDefenderInventory.IsPresent) {
        $installedApps = @(Invoke-AdvancedHuntingQuery -Query (Get-DefenderInstalledSoftwareQuery -Limit $TopRows) -Name 'Defender installed software inventory')
    }

    $intuneApps = @()
    if ($IncludeIntuneDetectedApps.IsPresent) { $intuneApps = @(Get-IntuneDetectedApps) }
    $controlView = @(Merge-AppControlView -InUseApps $inUseApps -InstalledApps $installedApps -IntuneApps $intuneApps)

    $summary = @(
        [PSCustomObject]@{ Metric = 'GeneratedAt'; Value = (Get-Date).ToString('s') }
        [PSCustomObject]@{ Metric = 'TenantId'; Value = $context.TenantId }
        [PSCustomObject]@{ Metric = 'LookbackDays'; Value = $LookbackDays }
        [PSCustomObject]@{ Metric = 'InUseApplications'; Value = $inUseApps.Count }
        [PSCustomObject]@{ Metric = 'DefenderInstalledApplications'; Value = $installedApps.Count }
        [PSCustomObject]@{ Metric = 'IntuneDetectedApplications'; Value = $intuneApps.Count }
        [PSCustomObject]@{ Metric = 'MergedControlRows'; Value = $controlView.Count }
        [PSCustomObject]@{ Metric = 'Workbook'; Value = $OutputPath }
        [PSCustomObject]@{ Metric = 'Log'; Value = $logPath }
    )

    if (Test-Path -Path $OutputPath) { Remove-Item -Path $OutputPath -Force }
    Export-WorksheetSafe -Rows $summary -WorksheetName 'Summary' -Path $OutputPath -ClearSheet
    Export-WorksheetSafe -Rows $controlView -WorksheetName 'ControlView' -Path $OutputPath -ClearSheet
    Export-WorksheetSafe -Rows $inUseApps -WorksheetName 'DefenderInUse' -Path $OutputPath -ClearSheet
    if (-not $SkipDefenderInventory.IsPresent) { Export-WorksheetSafe -Rows $installedApps -WorksheetName 'DefenderInstalled' -Path $OutputPath -ClearSheet }
    if ($IncludeIntuneDetectedApps.IsPresent) { Export-WorksheetSafe -Rows $intuneApps -WorksheetName 'IntuneDetected' -Path $OutputPath -ClearSheet }

    Write-Log -Message ("Export complete: {0}" -f $OutputPath)
    Write-Host "Export complete: $OutputPath"
    exit 0
}
catch {
    Write-Log -Message ("Script failed: {0}" -f $_.Exception.Message) -Level ERROR
    Write-Error $_
    exit 1
}
finally {
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
    catch { Write-Log -Message ("Disconnect-MgGraph failed: {0}" -f $_.Exception.Message) -Level WARNING }
}
