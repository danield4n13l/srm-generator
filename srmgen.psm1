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
        # Fallback for UNC or non-drive paths
        $drive = "UNC"
    }

    $folderName = Split-Path $resolvedPath -Leaf
    if ([string]::IsNullOrWhiteSpace($folderName)) {
        $folderName = "Root"
    }

    return "${drive}_${folderName}.manifest.json"
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

            # Clean title: strip trailing ' - Shortcut' or ' Shortcut' and file extension
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
    Creates an ordered hashtable representing an entry in a Steam ROM Manager manifest.
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
        [bool]$AppendArgsToExecutable = $false
    )

    return [ordered]@{
        title                  = $Title
        target                 = $Target
        startIn                = $StartIn
        launchOptions          = $LaunchOptions
        appendArgsToExecutable = $AppendArgsToExecutable
    }
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
    Saves an array of manifest entries as a formatted JSON manifest file, supporting append and deduplication.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Manifests,

        [Parameter(Mandatory = $true)]
        [string]$Path,

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
        # Deduplicate incoming entries among themselves if any duplicate targets exist
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
        # Ensure parent directory exists
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

    # Attach temporary row index
    $rowIndex = 1
    foreach ($m in $Manifests) {
        $m.Insert(0, "#", $rowIndex)
        $rowIndex++
    }

    $esc = [char]27
    Write-Host -NoNewline "$esc[?1049h" # Enter alternate screen buffer

    try {
        while ($true) {
            Write-Host -NoNewline "$esc[H$esc[2J" # Clear buffer and home cursor

            # Display table
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
        Write-Host -NoNewline "$esc[?1049l" # Restore main screen buffer
    }

    # Clean up temporary row index
    foreach ($m in $Manifests) {
        $m.Remove("#")
    }

    return ,$Manifests
}

Export-ModuleMember -Function @(
    'Get-SrmTargetKey',
    'Get-SrmDefaultManifestFileName',
    'ConvertFrom-LnkShortcut',
    'New-SrmManifestEntry',
    'Import-SrmManifest',
    'Export-SrmManifest',
    'Read-SrmHostPrefilled',
    'Invoke-SrmInteractivePrompt',
    'Invoke-SrmTui'
)
