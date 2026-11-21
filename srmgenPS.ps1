<#
.NAME
Steam ROM Manager - External Shortcut importer and generator
.SYNOPSIS
srmgenPS.ps1 is a PowerShell script that imports and generates external shortcuts for Steam ROM Manager.
.DESCRIPTION
This script parses Windows shortcuts (.lnk) and generates JSON manifests for Steam ROM Manager.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to a directory containing .lnk files (or a single .lnk file, or .json for EditMode)")]
    [string]$InputPath,

    [Parameter(Mandatory = $false, HelpMessage = "Path to the output directory where the manifest will be saved")]
    [string]$OutputPath,

    [Parameter(Mandatory = $false, HelpMessage = "Overwrite the output manifest if it already exists")]
    [switch]$Force,

    [Alias('a')]
    [Parameter(Mandatory = $false, HelpMessage = "Append entries to the existing output manifest")]
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

# Basic validation for InputPath
if (!(Test-Path $InputPath)) {
    Write-Error "InputPath does not exist: $InputPath"
    return
}

# Resolve absolute paths
$InputPath = (Resolve-Path $InputPath).Path

# Handle OutputPath validation
if (-not $EditMode -and [string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Error "OutputPath is required when not in EditMode."
    return
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
            Write-Error "OutputPath must be a directory."
            return
        }
    }
}

# Check mutually exclusive switches
if ($Append -and $Force) {
    Write-Error "-Append and -Force cannot be used together."
    return
}

$manifests = @()
$files = @()

if ($EditMode) {
    if (!(Test-Path $InputPath -PathType Leaf) -or ($InputPath -notmatch '\.json$')) {
        Write-Error "In Edit mode, InputPath must be an existing .json manifest file."
        return
    }
    if (!$Interactive -and !$TUI) {
        Write-Warning "Edit mode specified but no interactive switch (-i or -t) provided. Copying file instead."
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $outFilePath = $InputPath
    } else {
        $outFileName = Split-Path $InputPath -Leaf
        $outFilePath = Join-Path $OutputPath $outFileName
    }

    $manifests = Import-SrmManifest -Path $InputPath
}
else {
    # Determine the default output file name based on InputPath's drive and folder name
    $outFileName = Get-SrmDefaultManifestFileName -Path $InputPath
    $outFilePath = Join-Path $OutputPath $outFileName

    # Collect target .lnk files
    if (Test-Path $InputPath -PathType Leaf) {
        if ($InputPath -match '\.lnk$') {
            $files += Get-Item $InputPath
        }
        else {
            Write-Error "Input file must be a .lnk file."
            return
        }
    }
    elseif (Test-Path $InputPath -PathType Container) {
        $files = @(Get-ChildItem -Path $InputPath -Filter "*.lnk" -File)
    }

    if ($files.Count -eq 0) {
        Write-Warning "No .lnk files found in the input path: $InputPath"
        return
    }
}

# Check if output exists and prompt if needed
$outputExists = Test-Path $outFilePath -PathType Leaf
if ($outputExists -and -not $Append -and -not $Force) {
    if ($WhatIfPreference) {
        Write-Warning "Output file exists. Specify -Append or -Force with -WhatIf to preview the intended action."
        return
    }

    do {
        $outputChoice = (Read-Host "Output file exists. [A]ppend, [O]verwrite, or [C]ancel?").Trim().ToUpperInvariant()
        switch ($outputChoice) {
            { $_ -in @('A', 'APPEND') } { $Append = $true }
            { $_ -in @('O', 'OVERWRITE') } { $Force = $true }
            { $_ -in @('C', 'CANCEL', '') } { return }
            default { Write-Warning "Choose A to append, O to overwrite, or C to cancel." }
        }
    } while (-not $Append -and -not $Force)
}

$existingTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$seenInputTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if ($Append -and $outputExists) {
    $existingEntries = Import-SrmManifest -Path $outFilePath
    foreach ($existingManifest in $existingEntries) {
        $targetKey = Get-SrmTargetKey $existingManifest
        if ($null -ne $targetKey) { [void]$existingTargets.Add($targetKey) }
    }

    if ($EditMode) {
        $manifests = @($manifests | Where-Object {
            $targetKey = Get-SrmTargetKey $_
            if ($null -eq $targetKey) { return $true }
            if ($existingTargets.Contains($targetKey) -or -not $seenInputTargets.Add($targetKey)) {
                Write-Host "Skipping existing target: $targetKey"
                return $false
            }
            return $true
        })
    }
}

# Process .lnk files if not in Edit mode
if (-not $EditMode) {
    foreach ($file in $files) {
        Write-Host "Parsing: $($file.Name)"
        $shortcutInfo = ConvertFrom-LnkShortcut -Path $file.FullName
        if ($null -eq $shortcutInfo) { continue }

        $parsedTarget = $shortcutInfo.Target
        $cleanTitle = $shortcutInfo.Title
        $parsedStartIn = $shortcutInfo.StartIn
        $parsedLaunchOptions = $shortcutInfo.LaunchOptions

        if ($Append -and $outputExists) {
            $targetKey = ([string]$parsedTarget).Trim()
            if (![string]::IsNullOrWhiteSpace($targetKey) -and
                ($existingTargets.Contains($targetKey) -or -not $seenInputTargets.Add($targetKey))) {
                Write-Host "Skipping existing target: $targetKey"
                continue
            }
        }

        $manifest = New-SrmManifestEntry `
            -Title $cleanTitle `
            -Target $parsedTarget `
            -StartIn $parsedStartIn `
            -LaunchOptions $parsedLaunchOptions `
            -AppendArgsToExecutable $false

        $manifests += $manifest
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

# Export manifest
Export-SrmManifest -Manifests $manifests -Path $outFilePath -Append:$Append -Force:$Force

if (-not $EditMode) {
    Write-Host "Done! Processed $($files.Count) shortcut(s)."
}
else {
    Write-Host "Done! Processed $($manifests.Count) manifest entries."
}
