<#
.NAME
Steam ROM Manager - External Shortcut Importer & Manifest Generator
.SYNOPSIS
srmgenPS.ps1 is a high-performance, multi-threaded PowerShell script that imports and generates
external shortcut manifests for Steam ROM Manager (SRM).
.DESCRIPTION
Scans one or multiple directories of Windows shortcuts (.lnk), extracts launch parameters,
caches shortcut hashes in a database to skip unmodified files on subsequent scans, supports
templates and recent settings, and exports manifests per folder, per game, or merged into a single file.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Alias('InputPath', 'Path', 'Paths', 'p')]
    [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, HelpMessage = "Path(s) to directory/directories containing .lnk files (or single .lnk, or .json for EditMode)")]
    [string[]]$InputPaths,

    [Alias('o', 'Out')]
    [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Path to the output directory where manifest file(s) will be saved")]
    [string]$OutputPath,

    [Parameter(Mandatory = $false, HelpMessage = "Custom output filename (used for Merged/SingleFile mode)")]
    [string]$OutputFile,

    [Alias('Mode', 'm')]
    [Parameter(Mandatory = $false, HelpMessage = "Output mode: 'PerFolder' (collated per directory), 'PerGame' / 'Individual' (separate file per game), or 'Merged' (single JSON manifest)")]
    [ValidateSet('PerFolder', 'PerGame', 'Individual', 'Merged', 'SingleFile')]
    [string]$OutputMode = 'PerFolder',

    [Parameter(Mandatory = $false, HelpMessage = "Manifest template to use: 'default', 'artwork', or path to a custom JSON template")]
    [string]$Template = 'default',

    [Parameter(Mandatory = $false, HelpMessage = "Path to the shortcut manifest database file for hash caching")]
    [string]$DatabasePath,

    [Parameter(Mandatory = $false, HelpMessage = "Skip shortcuts that are already in the database and have not been modified")]
    [switch]$SkipUnmodified,

    [Parameter(Mandatory = $false, HelpMessage = "Disable database caching and force fresh re-parse of all shortcuts")]
    [switch]$NoCache,

    [Parameter(Mandatory = $false, HelpMessage = "Number of worker threads for parallel shortcut scanning")]
    [int]$Threads = [System.Environment]::ProcessorCount,

    [Parameter(Mandatory = $false, HelpMessage = "Overwrite the output manifest(s) without confirmation prompt")]
    [switch]$Force,

    [Alias('a')]
    [Parameter(Mandatory = $false, HelpMessage = "Append entries to the existing output manifest(s)")]
    [switch]$Append,

    [Alias('i')]
    [Parameter(Mandatory = $false, HelpMessage = "Interactively modify properties sequentially")]
    [switch]$Interactive,

    [Alias('t')]
    [Parameter(Mandatory = $false, HelpMessage = "Launch a spreadsheet-like TUI editor after parsing")]
    [switch]$TUI,

    [Alias('e')]
    [Parameter(Mandatory = $false, HelpMessage = "Edit an existing manifest JSON file instead of parsing .lnk files")]
    [switch]$EditMode
)

# Import core srmgen module
$moduleManifestPath = Join-Path $PSScriptRoot "srmgen.psd1"
if (Test-Path $moduleManifestPath) {
    Import-Module $moduleManifestPath -Force
} else {
    Import-Module (Join-Path $PSScriptRoot "srmgen.psm1") -Force
}

# If no arguments provided, launch the interactive setup wizard
if ($null -eq $InputPaths -or $InputPaths.Count -eq 0) {
    if ([Environment]::UserInteractive) {
        $wizard = Invoke-SrmWizard
        if ($null -eq $wizard) {
            Write-Warning "Setup wizard was cancelled."
            return
        }
        $InputPaths   = $wizard.InputPaths
        $OutputPath   = $wizard.OutputPath
        $EditMode     = $wizard.EditMode
        $OutputMode   = $wizard.OutputMode
        $Template     = $wizard.Template
        $TUI          = $wizard.TUI
        $Interactive  = $wizard.Interactive
    }
    else {
        Write-Error "InputPaths is required in non-interactive sessions."
        return
    }
}

# Load settings and database
$settings = Get-SrmSettings
$database = if (-not $NoCache) { Get-SrmDatabase -DatabasePath $DatabasePath } else { $null }

# Resolve input paths
$resolvedInputPaths = @()
foreach ($p in $InputPaths) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    if (!(Test-Path $p)) {
        Write-Warning "Input path does not exist: $p"
        continue
    }
    $resolvedInputPaths += (Resolve-Path $p).Path
}

if ($resolvedInputPaths.Count -eq 0) {
    Write-Error "No valid input paths specified."
    return
}

# Handle OutputPath validation / default
if (-not $EditMode -and [string]::IsNullOrWhiteSpace($OutputPath)) {
    $firstInput = $resolvedInputPaths[0]
    $OutputPath = if (Test-Path $firstInput -PathType Leaf) { Split-Path $firstInput } else { $firstInput }
    Write-Host "No OutputPath specified; defaulting to: $OutputPath" -ForegroundColor Gray
}

if (![string]::IsNullOrWhiteSpace($OutputPath)) {
    if (!(Test-Path $OutputPath)) {
        if ($PSCmdlet.ShouldProcess($OutputPath, "Create output directory")) {
            New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
        }
    }
    else {
        $OutputPath = (Resolve-Path $OutputPath).Path
        if (!(Test-Path $OutputPath -PathType Container)) {
            Write-Error "OutputPath must be a directory: $OutputPath"
            return
        }
    }
}

# Check mutually exclusive switches
if ($Append -and $Force) {
    Write-Error "-Append and -Force cannot be used together."
    return
}

# Load template definition
$templateObj = Get-SrmTemplate -Template $Template

$manifests = @()

if ($EditMode) {
    $singleInput = $resolvedInputPaths[0]
    if (!(Test-Path $singleInput -PathType Leaf) -or ($singleInput -notmatch '\.json$')) {
        Write-Error "In Edit mode, input must be an existing .json manifest file."
        return
    }
    if (!$Interactive -and !$TUI) {
        Write-Warning "Edit mode specified but no interactive switch (-i or -t) provided. Copying/validating file."
    }

    $outFilePath = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $singleInput
    } else {
        $leaf = Split-Path $singleInput -Leaf
        Join-Path $OutputPath $leaf
    }

    $manifests = Import-SrmManifest -Path $singleInput
}
else {
    # Scan shortcuts across all specified folders in parallel with database hash caching
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " Steam ROM Manager - Shortcut Importer" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "Source Folders : $($resolvedInputPaths -join ', ')"
    Write-Host "Output Mode    : $OutputMode"
    Write-Host "Output Target  : $OutputPath"
    Write-Host "Threads        : $Threads"
    Write-Host "Cache Database : $(if ($database) { $database.FilePath } else { 'Disabled' })"
    Write-Host ""

    $progressCallback = {
        param($curr, $tot, $file, $status)
        try {
            $pct = if ($tot -gt 0) { [int](($curr / $tot) * 100) } else { 0 }
            Write-Progress -Activity "Parsing Shortcuts" -Status "$status ($curr of $tot)" -PercentComplete $pct
        } catch {}
    }

    $manifests = Invoke-SrmParallelScan `
        -InputPaths $resolvedInputPaths `
        -Database $database `
        -Template $templateObj `
        -SkipUnmodified:$SkipUnmodified `
        -ThreadCount $Threads `
        -OnProgress $progressCallback

    try { Write-Progress -Activity "Parsing Shortcuts" -Completed } catch {}

    # Save updated database cache
    if ($null -ne $database) {
        Save-SrmDatabase -Database $database
    }

    # Update recent settings
    if ($null -ne $settings) {
        $folderList = @($settings.RecentInputFolders)
        foreach ($folder in $resolvedInputPaths) {
            if (Test-Path $folder -PathType Container) {
                $folderList = @($folder) + @($folderList | Where-Object { $_ -ne $folder })
            }
        }
        $settings.RecentInputFolders = @($folderList | Select-Object -First 15)
        $settings.LastOutputPath     = $OutputPath
        $settings.LastOutputMode     = $OutputMode
        $settings.LastTemplate       = $Template
        Save-SrmSettings -Settings $settings
    }

    if ($manifests.Count -eq 0) {
        Write-Warning "No shortcut entries available to export."
        return
    }
}

# Sequential interactive modification
if ($Interactive) {
    $manifests = Invoke-SrmInteractivePrompt -Manifests $manifests
}

# TUI spreadsheet-like editor
if ($TUI) {
    $manifests = Invoke-SrmTui -Manifests $manifests
}

# Export manifest(s)
Write-Host "`nExporting manifest(s)..." -ForegroundColor Cyan

$finalDestination = if ($OutputMode -in @('Merged', 'SingleFile')) {
    if (![string]::IsNullOrWhiteSpace($OutputFile)) {
        if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path $OutputPath $OutputFile }
    } else {
        $defaultFileName = Get-SrmDefaultManifestFileName -Path $resolvedInputPaths[0]
        Join-Path $OutputPath $defaultFileName
    }
} else {
    $OutputPath
}

$written = Export-SrmManifest `
    -Manifests $manifests `
    -Path $finalDestination `
    -OutputMode $OutputMode `
    -Append:$Append `
    -Force:$Force `
    -PassThru:$true

Write-Host "Done! Processed $($manifests.Count) shortcut(s)." -ForegroundColor Green
if ($written -and $written.Count -gt 0) {
    Write-Host "Generated file(s):" -ForegroundColor Green
    foreach ($w in $written) {
        Write-Host "  -> $w" -ForegroundColor White
    }
}
