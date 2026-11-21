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

# Basic validation for InputPath
if (!(Test-Path $InputPath)) {
    Write-Error "InputPath does not exist: $InputPath"
    exit 1
}

# Resolve absolute paths
$InputPath = (Resolve-Path $InputPath).Path

# Handle OutputPath creation if it doesn't exist
if (-not $EditMode -and [string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Error "OutputPath is required when not in EditMode."
    exit 1
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
            exit 1
        }
    }
}

function Read-HostPrefilled {
    param(
        [string]$Prompt,
        [string]$DefaultValue
    )
    if (![string]::IsNullOrEmpty($DefaultValue)) {
        if (Get-Module PSReadLine) {
            try {
                [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($DefaultValue)
            } catch {}
        }
        
        $res = Read-Host "$Prompt (Up to edit, Space to clear)"
        
        # If user just presses Enter, keep the original. 
        # If they want to clear it, they type a single space.
        Clear-History -Count 1 -CommandLine "$DefaultValue" -ErrorAction SilentlyContinue
        if ($res -eq "") { return $DefaultValue }
        if ($res -eq " ") { return "" }
        return $res
    }
    return Read-Host $Prompt
}

function Get-TargetKey {
    param([object]$Manifest)

    $target = [string]$Manifest.target
    if ([string]::IsNullOrWhiteSpace($target)) { return $null }
    return $target.Trim()
}

$manifests = @()
$files = @()

if ($EditMode) {
    if (!(Test-Path $InputPath -PathType Leaf) -or ($InputPath -notmatch '\.json$')) {
        Write-Error "In Edit mode, InputPath must be an existing .json manifest file."
        exit 1
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

    $json = Get-Content $InputPath -Raw | ConvertFrom-Json
    foreach ($item in $json) {
        $manifest = [ordered]@{}
        foreach ($prop in $item.PSObject.Properties) {
            $manifest[$prop.Name] = $prop.Value
        }
        $manifests += $manifest
    }
}
else {
    # Determine the output file name based on InputPath's drive and folder name
    $targetDir = if (Test-Path $InputPath -PathType Leaf) { Split-Path $InputPath } else { $InputPath }
    $drive = (Split-Path $targetDir -Qualifier).Replace(':', '')
    $folderName = Split-Path $targetDir -Leaf
    $outFileName = "${drive}_${folderName}.manifest.json"
    $outFilePath = Join-Path $OutputPath $outFileName

    # Collect target .lnk files
    if (Test-Path $InputPath -PathType Leaf) {
        if ($InputPath -match '\.lnk$') {
            $files += Get-Item $InputPath
        }
        else {
            Write-Error "Input file must be a .lnk file."
            exit 1
        }
    }
    elseif (Test-Path $InputPath -PathType Container) {
        $files = Get-ChildItem -Path $InputPath -Filter "*.lnk" -File
    }

    if ($files.Count -eq 0) {
        Write-Warning "No .lnk files found in the input path: $InputPath"
        exit 0
    }
}

# Resolve the action for an existing output before doing any shortcut parsing.
if ($Append -and $Force) {
    Write-Error "-Append and -Force cannot be used together."
    exit 1
}

$outputExists = Test-Path $outFilePath -PathType Leaf
if ($outputExists -and -not $Append -and -not $Force) {
    if ($WhatIfPreference) {
        Write-Warning "Output file exists. Specify -Append or -Force with -WhatIf to preview the intended action."
        exit 0
    }

    do {
        $outputChoice = (Read-Host "Output file exists. [A]ppend, [O]verwrite, or [C]ancel?").Trim().ToUpperInvariant()
        switch ($outputChoice) {
            { $_ -in @('A', 'APPEND') } { $Append = $true }
            { $_ -in @('O', 'OVERWRITE') } { $Force = $true }
            { $_ -in @('C', 'CANCEL', '') } { exit 0 }
            default { Write-Warning "Choose A to append, O to overwrite, or C to cancel." }
        }
    } while (-not $Append -and -not $Force)
}

$existingManifests = @()
$existingTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$seenInputTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($Append -and $outputExists) {
    $existingManifests = @(Get-Content -Path $outFilePath -Raw | ConvertFrom-Json)
    foreach ($existingManifest in $existingManifests) {
        $targetKey = Get-TargetKey $existingManifest
        if ($null -ne $targetKey) { [void]$existingTargets.Add($targetKey) }
    }

    if ($EditMode) {
        $manifests = @($manifests | Where-Object {
            $targetKey = Get-TargetKey $_
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
    # Initialize WScript.Shell for COM interop to parse .lnk files
    $WshShell = New-Object -ComObject WScript.Shell

    foreach ($file in $files) {
        Write-Host "Parsing: $($file.Name)"
        $shortcut = $WshShell.CreateShortcut($file.FullName)
        
        # Clean the title
        $cleanTitle = $file.BaseName -replace '\s*-?\s*Shortcut\s*$', ''
        $cleanTitle = $cleanTitle -replace '\.[^.]+$', ''
        
        # Extract raw properties
        $parsedTarget = $shortcut.TargetPath
        $parsedStartIn = $shortcut.WorkingDirectory
        $parsedLaunchOptions = $shortcut.Arguments

        if ($Append -and $outputExists) {
            $targetKey = ([string]$parsedTarget).Trim()
            if (![string]::IsNullOrWhiteSpace($targetKey) -and
                ($existingTargets.Contains($targetKey) -or -not $seenInputTargets.Add($targetKey))) {
                Write-Host "Skipping existing target: $targetKey"
                continue
            }
        }

        # Interactive sequential prompts
        if ($Interactive) {
            Write-Host "---"
            Write-Host "Modifying properties for: $($file.Name)" -ForegroundColor Cyan
            
            $promptTitle = Read-HostPrefilled "Title" $cleanTitle
            if (![string]::IsNullOrWhiteSpace($promptTitle)) { $cleanTitle = $promptTitle }
            
            $promptTarget = Read-HostPrefilled "Target" $parsedTarget
            if (![string]::IsNullOrWhiteSpace($promptTarget)) { $parsedTarget = $promptTarget }
            
            $promptStartIn = Read-HostPrefilled "Start In" $parsedStartIn
            if (![string]::IsNullOrWhiteSpace($promptStartIn)) { $parsedStartIn = $promptStartIn }
            
            $promptLaunchOptions = Read-HostPrefilled "Launch Options" $parsedLaunchOptions
            $parsedLaunchOptions = $promptLaunchOptions
        }
        
        # Map shortcut properties to the updated SRM manifest template
        $manifest = [ordered]@{
            title                  = $cleanTitle
            target                 = $parsedTarget
            startIn                = $parsedStartIn
            launchOptions          = $parsedLaunchOptions
            appendArgsToExecutable = $false
        }
        
        $manifests += $manifest
    }
}
elseif ($Interactive) {
    # Sequential edit for EditMode
    foreach ($manifest in $manifests) {
        Write-Host "---"
        Write-Host "Modifying properties for: $($manifest.title)" -ForegroundColor Cyan
        
        $promptTitle = Read-HostPrefilled "Title" $manifest.title
        if (![string]::IsNullOrWhiteSpace($promptTitle)) { $manifest.title = $promptTitle }
        
        $promptTarget = Read-HostPrefilled "Target" $manifest.target
        if (![string]::IsNullOrWhiteSpace($promptTarget)) { $manifest.target = $promptTarget }
        
        $promptStartIn = Read-HostPrefilled "Start In" $manifest.startIn
        if (![string]::IsNullOrWhiteSpace($promptStartIn)) { $manifest.startIn = $promptStartIn }
        
        $promptLaunchOptions = Read-HostPrefilled "Launch Options" $manifest.launchOptions
        $manifest.launchOptions = $promptLaunchOptions
    }
}

if ($TUI) {
    # Add '#' property for the TUI display
    $rowIndex = 1
    foreach ($m in $manifests) {
        $m.Insert(0, "#", $rowIndex)
        $rowIndex++
    }

    $esc = [char]27
    Write-Host -NoNewline "$esc[?1049h" # Enter alternate screen buffer
    
    try {
        while ($true) {
            Write-Host -NoNewline "$esc[H$esc[2J" # Clear alternate buffer and home cursor
            
            # Display the parsed shortcuts in a table by converting hashtables to PSCustomObject
            $manifests | ForEach-Object { [pscustomobject]$_ } | Format-Table -Property "#", title, target, startIn, launchOptions -AutoSize | Out-String | Write-Host
            
            $rowToEdit = Read-Host "Enter the row number to edit (or press Enter to finish)"
            if ([string]::IsNullOrWhiteSpace($rowToEdit)) {
                break
            }
            
            if ($rowToEdit -match '^\d+$' -and $rowToEdit -ge 1 -and $rowToEdit -le $manifests.Count) {
                $idx = [int]$rowToEdit - 1
                $item = $manifests[$idx]
                
                while ($true) {
                    Write-Host -NoNewline "$esc[H$esc[2J" # Clear alternate buffer and home cursor
                    
                    Write-Host "---"
                    Write-Host "Editing Row: $($rowToEdit) - $($item.title)" -ForegroundColor Yellow
                    Write-Host "1. Title          [$($item.title)]"
                    Write-Host "2. Target         [$($item.target)]"
                    Write-Host "3. Start In       [$($item.startIn)]"
                    Write-Host "4. Launch Options [$($item.launchOptions)]"
                    
                    $propChoice = Read-Host "Which property to edit? (1-4, press Enter to return to table)"
                    
                    if ([string]::IsNullOrWhiteSpace($propChoice)) {
                        break
                    }
                    
                    switch ($propChoice) {
                        '1' {
                            $newVal = Read-HostPrefilled "New Title" $item.title
                            if (![string]::IsNullOrWhiteSpace($newVal)) { $item.title = $newVal }
                        }
                        '2' {
                            $newVal = Read-HostPrefilled "New Target" $item.target
                            if (![string]::IsNullOrWhiteSpace($newVal)) { $item.target = $newVal }
                        }
                        '3' {
                            $newVal = Read-HostPrefilled "New Start In" $item.startIn
                            if (![string]::IsNullOrWhiteSpace($newVal)) { $item.startIn = $newVal }
                        }
                        '4' {
                            $newVal = Read-HostPrefilled "New Launch Options" $item.launchOptions
                            $item.launchOptions = $newVal
                        }
                    }
                }
            }
            else {
                Write-Warning "Invalid row number."
                Start-Sleep -Seconds 1
            }
        }
    }
    finally {
        Write-Host -NoNewline "$esc[?1049l" # Exit alternate screen buffer
    }

    # Clean up '#' property
    foreach ($m in $manifests) {
        $m.Remove("#")
    }
}

# Output as a single JSON array to the determined file path
$outputManifests = @($manifests)
if ($Append -and $outputExists) {
    $outputManifests = @($existingManifests)
    foreach ($manifest in $manifests) {
        $targetKey = Get-TargetKey $manifest
        if ($null -ne $targetKey -and $existingTargets.Contains($targetKey)) {
            Write-Host "Skipping target already present in output: $targetKey"
            continue
        }
        if ($null -ne $targetKey) { [void]$existingTargets.Add($targetKey) }
        $outputManifests += $manifest
    }
}

$writeAction = if ($Append -and $outputExists) { "Append manifest entries" } else { "Write manifest" }
if ($PSCmdlet.ShouldProcess($outFilePath, $writeAction)) {
    ConvertTo-Json -InputObject @($outputManifests) -Depth 10 | Set-Content -Path $outFilePath
    Write-Host "-> Generated single manifest: $outFilePath"
}

if (-not $EditMode) {
    Write-Host "Done! Processed $($files.Count) shortcut(s)."
}
else {
    Write-Host "Done! Processed $($manifests.Count) manifest entries."
}