<#
.NAME
Steam ROM Manager - External Shortcut importer and generator
.SYNOPSIS
srmgenPS.ps1 is a PowerShell script that imports and generates external shortcuts for Steam ROM Manager.
.DESCRIPTION
This script parses Windows shortcuts (.lnk) and generates JSON manifests for Steam ROM Manager.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to a directory containing .lnk files (or a single .lnk file)")]
    [string]$InputPath,

    [Parameter(Mandatory = $true, HelpMessage = "Path to the output directory where the manifest will be saved")]
    [string]$OutputPath,

    [Parameter(Mandatory = $false, HelpMessage = "Overwrite the output manifest if it already exists")]
    [switch]$Force,

    [Alias('i')]
    [Parameter(Mandatory = $false, HelpMessage = "Interactively modify properties sequentially")]
    [switch]$Interactive,

    [Alias('t')]
    [Parameter(Mandatory = $false, HelpMessage = "Launch a spreadsheet-like TUI editor after parsing")]
    [switch]$TUI
)

# Basic validation for InputPath
if (!(Test-Path $InputPath)) {
    Write-Error "InputPath does not exist: $InputPath"
    exit 1
}

# Resolve absolute paths
$InputPath = (Resolve-Path $InputPath).Path

# Handle OutputPath creation if it doesn't exist
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
}
else {
    $OutputPath = (Resolve-Path $OutputPath).Path
    if (!(Test-Path $OutputPath -PathType Container)) {
        Write-Error "OutputPath must be a directory."
        exit 1
    }
}

# Determine the output file name based on InputPath's drive and folder name
$targetDir = if (Test-Path $InputPath -PathType Leaf) { Split-Path $InputPath } else { $InputPath }
$drive = (Split-Path $targetDir -Qualifier).Replace(':', '')
$folderName = Split-Path $targetDir -Leaf
$outFileName = "${drive}_${folderName}.manifest.json"
$outFilePath = Join-Path $OutputPath $outFileName

# Check if output file exists to prevent accidental overwrite
if ((Test-Path $outFilePath) -and -not $Force) {
    Write-Error "Output file already exists: $outFilePath. Use -Force to overwrite."
    exit 1
}

# Initialize WScript.Shell for COM interop to parse .lnk files
$WshShell = New-Object -ComObject WScript.Shell

# Collect target .lnk files
$files = @()
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

$manifests = @()

foreach ($file in $files) {
    Write-Host "Parsing: $($file.Name)"
    $shortcut = $WshShell.CreateShortcut($file.FullName)
    
    # Clean the title (e.g., remove " - Shortcut" or "- Shortcut" from the end)
    $cleanTitle = $file.BaseName -replace '\s*-?\s*Shortcut\s*$', ''
    # Remove any remaining file extension (like .exe)
    $cleanTitle = $cleanTitle -replace '\.[^.]+$', ''
    
    # Extract raw properties
    $parsedTarget = $shortcut.TargetPath
    $parsedStartIn = $shortcut.WorkingDirectory
    $parsedLaunchOptions = $shortcut.Arguments

    # Interactive mode prompts
    if ($Interactive) {
        Write-Host "---"
        Write-Host "Modifying properties for: $($file.Name)" -ForegroundColor Cyan
        
        $promptTitle = Read-Host "Title [$cleanTitle]"
        if (![string]::IsNullOrWhiteSpace($promptTitle)) { $cleanTitle = $promptTitle }
        
        $promptTarget = Read-Host "Target [$parsedTarget]"
        if (![string]::IsNullOrWhiteSpace($promptTarget)) { $parsedTarget = $promptTarget }
        
        $promptStartIn = Read-Host "Start In [$parsedStartIn]"
        if (![string]::IsNullOrWhiteSpace($promptStartIn)) { $parsedStartIn = $promptStartIn }
        
        $promptLaunchOptions = Read-Host "Launch Options [$parsedLaunchOptions]"
        # Launch options can legitimately be blanked out interactively, but simple Enter = keep original
        if ($promptLaunchOptions -ne "") { $parsedLaunchOptions = $promptLaunchOptions }
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
            
            Write-Host "---"
            Write-Host "Editing Row: $($rowToEdit) - $($item.title)" -ForegroundColor Yellow
            Write-Host "1. Title          [$($item.title)]"
            Write-Host "2. Target         [$($item.target)]"
            Write-Host "3. Start In       [$($item.startIn)]"
            Write-Host "4. Launch Options [$($item.launchOptions)]"
            
            $propChoice = Read-Host "Which property to edit? (1-4, press Enter to cancel)"
            
            switch ($propChoice) {
                '1' {
                    $newVal = Read-Host "New Title"
                    if (![string]::IsNullOrWhiteSpace($newVal)) { $item.title = $newVal }
                }
                '2' {
                    $newVal = Read-Host "New Target"
                    if (![string]::IsNullOrWhiteSpace($newVal)) { $item.target = $newVal }
                }
                '3' {
                    $newVal = Read-Host "New Start In"
                    if (![string]::IsNullOrWhiteSpace($newVal)) { $item.startIn = $newVal }
                }
                '4' {
                    $newVal = Read-Host "New Launch Options"
                    if ($newVal -ne "") { $item.launchOptions = $newVal }
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
$manifests | ConvertTo-Json -Depth 10 | Set-Content -Path $outFilePath
Write-Host "-> Generated single manifest: $outFilePath"

Write-Host "Done! Processed $($files.Count) shortcut(s)."