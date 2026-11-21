#
# srmgen.psm1 - Steam ROM Manager Manifest Generator Module
#

function Get-SrmTargetKey {
    <#
    .SYNOPSIS
    Returns a normalized, trimmed target string for manifest deduplication.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Manifest
    )

    $target = [string]$Manifest.target
    if ([string]::IsNullOrWhiteSpace($target)) { return $null }
    return $target.Trim()
}

function Get-SrmDefaultManifestFileName {
    <#
    .SYNOPSIS
    Generates a default manifest filename based on drive and directory name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = if (Test-Path $Path -PathType Leaf) { Split-Path $Path } else { $Path }
    $resolvedPath = (Resolve-Path $resolvedPath).Path

    $qualifier = Split-Path $resolvedPath -Qualifier
    if (![string]::IsNullOrWhiteSpace($qualifier)) {
        $drive = $qualifier.Replace(':', '').Replace('\', '')
    } else {
        $drive = "UNC"
    }

    $folderName = Split-Path $resolvedPath -Leaf
    if ([string]::IsNullOrWhiteSpace($folderName)) {
        $folderName = "Root"
    }

    return "${drive}_${folderName}.manifest.json"
}

function Get-SrmTemplate {
    <#
    .SYNOPSIS
    Loads a manifest template definition from a preset name or JSON file path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Template = 'default'
    )

    if ([string]::IsNullOrWhiteSpace($Template) -or $Template -eq 'default') {
        return [ordered]@{
            title                  = '{{title}}'
            target                 = '{{target}}'
            startIn                = '{{startIn}}'
            launchOptions          = '{{launchOptions}}'
            appendArgsToExecutable = $false
        }
    }

    if ($Template -eq 'artwork') {
        $builtInArtwork = Join-Path $PSScriptRoot "templates\artwork.template.json"
        if (Test-Path $builtInArtwork) {
            $parsed = Get-Content $builtInArtwork -Raw | ConvertFrom-Json
            $order = [ordered]@{}
            foreach ($p in $parsed.PSObject.Properties) { $order[$p.Name] = $p.Value }
            return $order
        }
        return [ordered]@{
            title                  = '{{title}}'
            target                 = '{{target}}'
            startIn                = '{{startIn}}'
            launchOptions          = '{{launchOptions}}'
            appendArgsToExecutable = $false
            cover                  = ''
            icon                   = ''
            hero                   = ''
            logo                   = ''
            banner                 = ''
        }
    }

    if (Test-Path $Template -PathType Leaf) {
        $parsed = Get-Content -Path $Template -Raw | ConvertFrom-Json
        $order = [ordered]@{}
        foreach ($p in $parsed.PSObject.Properties) { $order[$p.Name] = $p.Value }
        return $order
    }

    $templateInDir = Join-Path $PSScriptRoot "templates\$Template"
    if (Test-Path $templateInDir -PathType Leaf) {
        $parsed = Get-Content -Path $templateInDir -Raw | ConvertFrom-Json
        $order = [ordered]@{}
        foreach ($p in $parsed.PSObject.Properties) { $order[$p.Name] = $p.Value }
        return $order
    }

    $templateWithExt = Join-Path $PSScriptRoot "templates\$Template.template.json"
    if (Test-Path $templateWithExt -PathType Leaf) {
        $parsed = Get-Content -Path $templateWithExt -Raw | ConvertFrom-Json
        $order = [ordered]@{}
        foreach ($p in $parsed.PSObject.Properties) { $order[$p.Name] = $p.Value }
        return $order
    }

    Write-Warning "Template '$Template' not found. Using default template."
    return [ordered]@{
        title                  = '{{title}}'
        target                 = '{{target}}'
        startIn                = '{{startIn}}'
        launchOptions          = '{{launchOptions}}'
        appendArgsToExecutable = $false
    }
}

function ConvertFrom-LnkShortcut {
    <#
    .SYNOPSIS
    Parses a Windows shortcut (.lnk) file and extracts its target, arguments, and metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string]$Path
    )

    process {
        if (!(Test-Path $Path -PathType Leaf)) {
            Write-Error "Shortcut file not found: $Path"
            return
        }

        $item = Get-Item $Path
        if ($item.Extension -ne '.lnk') {
            Write-Error "File is not a .lnk shortcut: $Path"
            return
        }

        $WshShell = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $WshShell.CreateShortcut($item.FullName)

            $cleanTitle = $item.BaseName -replace '\s*-?\s*Shortcut\s*$', ''
            $cleanTitle = $cleanTitle -replace '\.[^.]+$', ''

            [pscustomobject]@{
                Title         = $cleanTitle
                Target        = [string]$shortcut.TargetPath
                StartIn       = [string]$shortcut.WorkingDirectory
                LaunchOptions = [string]$shortcut.Arguments
                SourceFile    = $item.FullName
            }
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($WshShell) | Out-Null
        }
    }
}

function New-SrmManifestEntry {
    <#
    .SYNOPSIS
    Creates an ordered hashtable representing an entry in a Steam ROM Manager manifest, optionally applying a template.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $false)]
        [string]$StartIn = '',

        [Parameter(Mandatory = $false)]
        [string]$LaunchOptions = '',

        [Parameter(Mandatory = $false)]
        [bool]$AppendArgsToExecutable = $false,

        [Parameter(Mandatory = $false)]
        [object]$Template
    )

    if ($null -eq $Template) {
        return [ordered]@{
            title                  = $Title
            target                 = $Target
            startIn                = $StartIn
            launchOptions          = $LaunchOptions
            appendArgsToExecutable = $AppendArgsToExecutable
        }
    }

    $entry = [ordered]@{}
    $props = if ($Template -is [System.Management.Automation.PSCustomObject]) {
        $Template.PSObject.Properties
    } else {
        $Template.GetEnumerator()
    }

    foreach ($prop in $props) {
        $val = $prop.Value
        if ($val -is [string]) {
            $replaced = $val
            $replaced = $replaced -replace '\{\{\s*title\s*\}\}|\$\{title\}', $Title
            $replaced = $replaced -replace '\{\{\s*target\s*\}\}|\$\{target\}', $Target
            $replaced = $replaced -replace '\{\{\s*startIn\s*\}\}|\$\{startIn\}', $StartIn
            $replaced = $replaced -replace '\{\{\s*launchOptions\s*\}\}|\$\{launchOptions\}', $LaunchOptions
            $entry[$prop.Name] = $replaced
        } else {
            $entry[$prop.Name] = $val
        }
    }

    # Ensure essential SRM keys exist
    if (-not $entry.Contains('title')) { $entry['title'] = $Title }
    if (-not $entry.Contains('target')) { $entry['target'] = $Target }
    if (-not $entry.Contains('startIn')) { $entry['startIn'] = $StartIn }
    if (-not $entry.Contains('launchOptions')) { $entry['launchOptions'] = $LaunchOptions }
    if (-not $entry.Contains('appendArgsToExecutable')) { $entry['appendArgsToExecutable'] = $AppendArgsToExecutable }

    return $entry
}

function Import-SrmManifest {
    <#
    .SYNOPSIS
    Reads an existing SRM manifest JSON file into an array of ordered entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (!(Test-Path $Path -PathType Leaf)) {
        Write-Error "Manifest file not found: $Path"
        return @()
    }

    $rawContent = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($rawContent)) {
        return @()
    }

    $json = $rawContent | ConvertFrom-Json
    $manifests = @()

    foreach ($item in $json) {
        $manifest = [ordered]@{}
        foreach ($prop in $item.PSObject.Properties) {
            $manifest[$prop.Name] = $prop.Value
        }
        $manifests += $manifest
    }

    return ,$manifests
}

function Export-SrmManifest {
    <#
    .SYNOPSIS
    Saves an array of manifest entries as formatted JSON manifest file(s), supporting append, deduplication, and individual file output.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Manifests,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Merged', 'Individual')]
        [string]$OutputMode = 'Merged',

        [Parameter(Mandatory = $false)]
        [switch]$Append,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    if ($Append -and $Force) {
        Write-Error "-Append and -Force cannot be used together."
        return
    }

    if ($OutputMode -eq 'Individual') {
        # Ensure output directory exists
        if (!(Test-Path $Path)) {
            if ($PSCmdlet.ShouldProcess($Path, "Create output directory")) {
                New-Item -ItemType Directory -Force -Path $Path | Out-Null
            }
        }

        $writtenFiles = @()
        foreach ($entry in $Manifests) {
            $cleanTitle = ([string]$entry.title).Trim()
            $safeTitle = ($cleanTitle -replace '[\\/:*?"<>|]', '_').Trim()
            if ([string]::IsNullOrWhiteSpace($safeTitle)) {
                $safeTitle = "Game_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
            }

            $individualFilePath = Join-Path $Path "$safeTitle.manifest.json"
            $individualExists = Test-Path $individualFilePath -PathType Leaf

            if ($individualExists -and -not $Force -and -not $Append) {
                Write-Warning "File already exists, skipping: $individualFilePath (use -Force to overwrite)"
                continue
            }

            if ($PSCmdlet.ShouldProcess($individualFilePath, "Write individual manifest")) {
                ConvertTo-Json -InputObject $entry -Depth 10 | Set-Content -Path $individualFilePath -Encoding UTF8
                Write-Host "-> Generated individual manifest: $individualFilePath"
                $writtenFiles += $individualFilePath
            }
        }

        if ($PassThru) {
            return ,$writtenFiles
        }
        return
    }

    # Merged output mode
    $outputExists = Test-Path $Path -PathType Leaf
    $finalEntries = @()
    $existingTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($Append -and $outputExists) {
        $existingEntries = Import-SrmManifest -Path $Path
        foreach ($entry in $existingEntries) {
            $key = Get-SrmTargetKey $entry
            if ($null -ne $key) { [void]$existingTargets.Add($key) }
            $finalEntries += $entry
        }

        foreach ($newEntry in $Manifests) {
            $key = Get-SrmTargetKey $newEntry
            if ($null -ne $key -and $existingTargets.Contains($key)) {
                Write-Host "Skipping target already present in output: $key"
                continue
            }
            if ($null -ne $key) { [void]$existingTargets.Add($key) }
            $finalEntries += $newEntry
        }
    }
    else {
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $Manifests) {
            $key = Get-SrmTargetKey $entry
            if ($null -ne $key) {
                if ($seen.Contains($key)) {
                    Write-Host "Skipping duplicate target in batch: $key"
                    continue
                }
                [void]$seen.Add($key)
            }
            $finalEntries += $entry
        }
    }

    $actionDesc = if ($Append -and $outputExists) { "Append manifest entries" } else { "Write manifest" }
    if ($PSCmdlet.ShouldProcess($Path, $actionDesc)) {
        $parentDir = Split-Path $Path -Parent
        if (![string]::IsNullOrWhiteSpace($parentDir) -and !(Test-Path $parentDir)) {
            New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
        }

        ConvertTo-Json -InputObject @($finalEntries) -Depth 10 | Set-Content -Path $Path -Encoding UTF8
        Write-Host "-> Generated manifest: $Path"
    }

    if ($PassThru) {
        return ,$finalEntries
    }
}

function Read-SrmHostPrefilled {
    <#
    .SYNOPSIS
    Prompts the user for input with an editable default value via PSReadLine history or fallback.
    #>
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

        Clear-History -Count 1 -CommandLine "$DefaultValue" -ErrorAction SilentlyContinue
        if ($res -eq "") { return $DefaultValue }
        if ($res -eq " ") { return "" }
        return $res
    }

    return Read-Host $Prompt
}

function Invoke-SrmInteractivePrompt {
    <#
    .SYNOPSIS
    Interactively prompts for and updates fields of manifest entries sequentially.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Manifests
    )

    foreach ($manifest in $Manifests) {
        Write-Host "---"
        Write-Host "Modifying properties for: $($manifest.title)" -ForegroundColor Cyan

        $promptTitle = Read-SrmHostPrefilled "Title" $manifest.title
        if (![string]::IsNullOrWhiteSpace($promptTitle)) { $manifest.title = $promptTitle }

        $promptTarget = Read-SrmHostPrefilled "Target" $manifest.target
        if (![string]::IsNullOrWhiteSpace($promptTarget)) { $manifest.target = $promptTarget }

        $promptStartIn = Read-SrmHostPrefilled "Start In" $manifest.startIn
        if (![string]::IsNullOrWhiteSpace($promptStartIn)) { $manifest.startIn = $promptStartIn }

        $promptLaunchOptions = Read-SrmHostPrefilled "Launch Options" $manifest.launchOptions
        $manifest.launchOptions = $promptLaunchOptions
    }

    return ,$Manifests
}

function Invoke-SrmTui {
    <#
    .SYNOPSIS
    Launches an alternate-screen console spreadsheet-like TUI editor to inspect and edit manifest entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Manifests
    )

    $rowIndex = 1
    foreach ($m in $Manifests) {
        $m.Insert(0, "#", $rowIndex)
        $rowIndex++
    }

    $esc = [char]27
    Write-Host -NoNewline "$esc[?1049h"

    try {
        while ($true) {
            Write-Host -NoNewline "$esc[H$esc[2J"

            $Manifests | ForEach-Object { [pscustomobject]$_ } | Format-Table -Property "#", title, target, startIn, launchOptions -AutoSize | Out-String | Write-Host

            $rowToEdit = Read-Host "Enter the row number to edit (or press Enter to finish)"
            if ([string]::IsNullOrWhiteSpace($rowToEdit)) {
                break
            }

            if ($rowToEdit -match '^\d+$' -and [int]$rowToEdit -ge 1 -and [int]$rowToEdit -le $Manifests.Count) {
                $idx = [int]$rowToEdit - 1
                $item = $Manifests[$idx]

                while ($true) {
                    Write-Host -NoNewline "$esc[H$esc[2J"

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
                            $newVal = Read-SrmHostPrefilled "New Title" $item.title
                            if (![string]::IsNullOrWhiteSpace($newVal)) { $item.title = $newVal }
                        }
                        '2' {
                            $newVal = Read-SrmHostPrefilled "New Target" $item.target
                            if (![string]::IsNullOrWhiteSpace($newVal)) { $item.target = $newVal }
                        }
                        '3' {
                            $newVal = Read-SrmHostPrefilled "New Start In" $item.startIn
                            if (![string]::IsNullOrWhiteSpace($newVal)) { $item.startIn = $newVal }
                        }
                        '4' {
                            $newVal = Read-SrmHostPrefilled "New Launch Options" $item.launchOptions
                            $item.launchOptions = $newVal
                        }
                    }
                }
            }
            else {
                Write-Warning "Invalid row number: $rowToEdit"
                Start-Sleep -Seconds 1
            }
        }
    }
    finally {
        Write-Host -NoNewline "$esc[?1049l"
    }

    foreach ($m in $Manifests) {
        $m.Remove("#")
    }

    return ,$Manifests
}

function Invoke-SrmWizard {
    <#
    .SYNOPSIS
    Runs an interactive guided setup wizard to collect arguments when none are provided.
    #>
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "     Steam ROM Manager - Manifest Generator Wizard       " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "No arguments provided. Guided setup will assist you." -ForegroundColor Gray
    Write-Host ""

    Write-Host "Select Operation Mode:" -ForegroundColor Yellow
    Write-Host "  [1] Generate manifest from Windows shortcuts (.lnk)"
    Write-Host "  [2] Edit an existing manifest file (.json)"
    $modeChoice = ""
    do {
        $modeChoice = (Read-Host "Choice [1/2, default: 1]").Trim()
        if ([string]::IsNullOrWhiteSpace($modeChoice)) { $modeChoice = "1" }
    } while ($modeChoice -notin @("1", "2"))

    if ($modeChoice -eq "2") {
        Write-Host "`n-- Edit Mode --" -ForegroundColor Yellow
        $jsonPath = ""
        do {
            $jsonPath = (Read-Host "Path to existing manifest (.json)").Trim().Trim('"').Trim("'")
            if (!(Test-Path $jsonPath -PathType Leaf) -or $jsonPath -notmatch '\.json$') {
                Write-Warning "File does not exist or is not a .json file. Please try again."
                $jsonPath = ""
            }
        } while ([string]::IsNullOrWhiteSpace($jsonPath))

        Write-Host "`nChoose an editor:" -ForegroundColor Yellow
        Write-Host "  [1] Spreadsheet-like TUI editor (recommended)"
        Write-Host "  [2] Sequential terminal prompts"
        Write-Host "  [3] None (copy/validate only)"
        $editChoice = (Read-Host "Choice [1/2/3, default: 1]").Trim()
        if ([string]::IsNullOrWhiteSpace($editChoice)) { $editChoice = "1" }

        $tui = ($editChoice -eq "1")
        $interactive = ($editChoice -eq "2")

        $outPath = (Read-Host "Output directory (press Enter to overwrite original file in place)").Trim().Trim('"').Trim("'")

        return @{
            InputPath   = $jsonPath
            OutputPath  = $outPath
            EditMode    = $true
            TUI         = $tui
            Interactive = $interactive
            OutputMode  = 'Merged'
            Template    = 'default'
        }
    }

    Write-Host "`n-- Shortcut Parsing Mode --" -ForegroundColor Yellow
    $inPath = ""
    do {
        $inPath = (Read-Host "Path to folder with .lnk shortcuts (or a single .lnk)").Trim().Trim('"').Trim("'")
        if (!(Test-Path $inPath)) {
            Write-Warning "Path '$inPath' does not exist. Please enter a valid path."
            $inPath = ""
        }
    } while ([string]::IsNullOrWhiteSpace($inPath))

    $defaultOut = if (Test-Path $inPath -PathType Leaf) { Split-Path $inPath } else { $inPath }
    $outDir = (Read-Host "Output directory [default: $defaultOut]").Trim().Trim('"').Trim("'")
    if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = $defaultOut }

    Write-Host "`nOutput Mode:" -ForegroundColor Yellow
    Write-Host "  [1] Single merged manifest file (recommended for SRM Manual parser)"
    Write-Host "  [2] Individual manifest files per game"
    $outModeChoice = (Read-Host "Choice [1/2, default: 1]").Trim()
    $outMode = if ($outModeChoice -eq "2") { 'Individual' } else { 'Merged' }

    Write-Host "`nManifest Template:" -ForegroundColor Yellow
    Write-Host "  [1] Standard SRM (title, target, startIn, launchOptions)"
    Write-Host "  [2] SRM with Artwork fields (adds cover, icon, hero, logo, banner)"
    Write-Host "  [3] Custom template file (.json)"
    $templateChoice = (Read-Host "Choice [1/2/3, default: 1]").Trim()
    $template = 'default'
    if ($templateChoice -eq "2") {
        $template = 'artwork'
    } elseif ($templateChoice -eq "3") {
        $customTpl = (Read-Host "Path to custom JSON template").Trim().Trim('"').Trim("'")
        if (Test-Path $customTpl) { $template = $customTpl } else { Write-Warning "File not found; using default." }
    }

    Write-Host "`nReview / Editing:" -ForegroundColor Yellow
    Write-Host "  [1] Save directly (batch mode)"
    Write-Host "  [2] Launch spreadsheet-like TUI editor before saving"
    Write-Host "  [3] Interactively edit each shortcut sequentially"
    $revChoice = (Read-Host "Choice [1/2/3, default: 1]").Trim()
    $tui = ($revChoice -eq "2")
    $interactive = ($revChoice -eq "3")

    Write-Host ""
    Write-Host "Starting generation..." -ForegroundColor Green

    return @{
        InputPath   = $inPath
        OutputPath  = $outDir
        EditMode    = $false
        OutputMode  = $outMode
        Template    = $template
        TUI         = $tui
        Interactive = $interactive
    }
}

Export-ModuleMember -Function @(
    'Get-SrmTargetKey',
    'Get-SrmDefaultManifestFileName',
    'Get-SrmTemplate',
    'ConvertFrom-LnkShortcut',
    'New-SrmManifestEntry',
    'Import-SrmManifest',
    'Export-SrmManifest',
    'Read-SrmHostPrefilled',
    'Invoke-SrmInteractivePrompt',
    'Invoke-SrmTui',
    'Invoke-SrmWizard'
)
