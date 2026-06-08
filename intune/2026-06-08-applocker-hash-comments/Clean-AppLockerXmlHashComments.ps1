<#
.SYNOPSIS
Fjerner hash-prefikserte kommentarlinjer fra en AppLocker XML-snutt.

.DESCRIPTION
Removes lines where the first non-whitespace character is # before AppLocker XML is saved or parsed.
This is intended for rough snippets where lines such as #msi or #./Vendor/... are comments or metadata,
not meaningful AppLocker policy XML. The script preserves all non-comment lines exactly, including
indentation, XML comments, and AppLocker element content. Optionally validates that the cleaned output is
well-formed XML.
#>

[CmdletBinding(DefaultParameterSetName = 'Path')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Text')]
    [ValidateNotNull()]
    [string]$LiteralText,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$ValidateXml
)

$ScriptName = 'Clean-AppLockerXmlHashComments'
$LogDirectory = 'C:\MK-LogFiles'
$LogPath = Join-Path -Path $LogDirectory -ChildPath "$ScriptName.log"

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Entry = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $Entry -Encoding UTF8
}

function Remove-HashCommentLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $NormalizedContent = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    $Lines = $NormalizedContent -split "`n", -1
    $KeptLines = New-Object System.Collections.Generic.List[string]
    $IgnoredCount = 0

    foreach ($Line in $Lines) {
        if ($Line -match '^\s*#') {
            $IgnoredCount++
            continue
        }

        $KeptLines.Add($Line)
    }

    [pscustomobject]@{
        Content = [string]::Join("`r`n", $KeptLines)
        IgnoredHashLineCount = $IgnoredCount
    }
}

try {
    if (-not (Test-Path -Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    Write-Log -Level 'INFO' -Message 'Starting AppLocker XML hash-comment cleanup.'

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -Path $InputPath -PathType Leaf)) {
            throw "InputPath not found: $InputPath"
        }

        $RawContent = Get-Content -Path $InputPath -Raw -Encoding UTF8
    }
    else {
        $RawContent = $LiteralText
    }

    $CleanResult = Remove-HashCommentLines -Content $RawContent

    if ($ValidateXml) {
        try {
            $XmlDocument = New-Object System.Xml.XmlDocument
            $XmlDocument.PreserveWhitespace = $true
            $XmlDocument.LoadXml($CleanResult.Content)
            Write-Log -Level 'INFO' -Message 'Cleaned content passed XML validation.'
        }
        catch {
            throw "Cleaned content is not well-formed XML: $($_.Exception.Message)"
        }
    }

    $OutputDirectory = Split-Path -Path $OutputPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory) -and -not (Test-Path -Path $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }

    Set-Content -Path $OutputPath -Value $CleanResult.Content -Encoding UTF8
    Write-Log -Level 'INFO' -Message "Cleanup complete. Ignored hash-prefixed lines: $($CleanResult.IgnoredHashLineCount). OutputPath: $OutputPath"
    Write-Output "Cleaned AppLocker XML written to: $OutputPath"
    Write-Output "Ignored hash-prefixed lines: $($CleanResult.IgnoredHashLineCount)"
    exit 0
}
catch {
    try {
        if (-not (Test-Path -Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }
        Write-Log -Level 'ERROR' -Message $_.Exception.Message
    }
    catch {
        Write-Error "Failed to write log entry: $($_.Exception.Message)"
    }

    Write-Error $_.Exception.Message
    exit 1
}
