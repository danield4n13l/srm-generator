#
# srmgen.psm1 - Steam ROM Manager Manifest Generator Module
# Enhanced with Multi-Threading, Hash Caching Database, and Recent Settings
#

function Get-SrmItemHash {
    <#
    .SYNOPSIS
    Computes a deterministic SHA256 hash of a shortcut's target executable and working directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $false)]
        [string]$StartIn = ''
    )

    $cleanTarget = if ($Target) { $Target.Trim().ToLowerInvariant() } else { '' }
    $cleanStartIn = if ($StartIn) { $StartIn.Trim().ToLowerInvariant() } else { '' }
    $composite = "$cleanTarget|$cleanStartIn"

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($composite)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $hasher.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
}

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

function Get-SrmDatabase {
    <#
    .SYNOPSIS
    Loads or initializes the shortcut manifest database from disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath
    )

    if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
        $DatabasePath = Join-Path $PSScriptRoot ".srm_database.json"
    }

    if (Test-Path $DatabasePath -PathType Leaf) {
        try {
            $raw = Get-Content -Path $DatabasePath -Raw -ErrorAction Stop
            if (![string]::IsNullOrWhiteSpace($raw)) {
                $db = $raw | ConvertFrom-Json
                $lookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                if ($db.shortcuts) {
                    foreach ($prop in $db.shortcuts.PSObject.Properties) {
                        $lookup[$prop.Name] = $prop.Value
                    }
                }
                return [pscustomobject]@{
                    Version   = [string]$db.version
                    UpdatedAt = [string]$db.updatedAt
                    Shortcuts = $lookup
                    FilePath  = (Resolve-Path $DatabasePath).Path
                }
            }
        } catch {
            Write-Warning "Could not read database at '$DatabasePath': $_. Initializing fresh database."
        }
    }

    return [pscustomobject]@{
        Version   = "1.0"
        UpdatedAt = (Get-Date).ToString("o")
        Shortcuts = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        FilePath  = $DatabasePath
    }
}

function Save-SrmDatabase {
    <#
    .SYNOPSIS
    Persists the shortcut manifest database to disk as formatted JSON.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Database,

        [Parameter(Mandatory = $false)]
        [string]$DatabasePath
    )

    $targetPath = if (![string]::IsNullOrWhiteSpace($DatabasePath)) { $DatabasePath } else { $Database.FilePath }
    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        $targetPath = Join-Path $PSScriptRoot ".srm_database.json"
    }

    $shortcutsDict = [ordered]@{}
    if ($Database.Shortcuts) {
        foreach ($k in $Database.Shortcuts.Keys) {
            $shortcutsDict[$k] = $Database.Shortcuts[$k]
        }
    }

    $exportObj = [ordered]@{
        version    = if ($Database.Version) { $Database.Version } else { "1.0" }
        updatedAt  = (Get-Date).ToString("o")
        totalCount = $shortcutsDict.Count
        shortcuts  = $shortcutsDict
    }

    if ($PSCmdlet.ShouldProcess($targetPath, "Save shortcut database")) {
        $dir = Split-Path $targetPath -Parent
        if (![string]::IsNullOrWhiteSpace($dir) -and !(Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $exportObj | ConvertTo-Json -Depth 10 | Set-Content -Path $targetPath -Encoding UTF8
    }
}

function Get-SrmSettings {
    <#
    .SYNOPSIS
    Loads recent application settings and folder history from disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SettingsPath
    )

    if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
        $SettingsPath = Join-Path $PSScriptRoot ".srm_settings.json"
    }

    if (Test-Path $SettingsPath -PathType Leaf) {
        try {
            $raw = Get-Content -Path $SettingsPath -Raw -ErrorAction Stop
            if (![string]::IsNullOrWhiteSpace($raw)) {
                $obj = $raw | ConvertFrom-Json
                $mode = if ($obj.lastOutputMode) { [string]$obj.lastOutputMode } else { "PerFolder" }
                $tpl  = if ($obj.lastTemplate) { [string]$obj.lastTemplate } else { "default" }
                $thm  = if ($obj.lastTheme) { [string]$obj.lastTheme } else { "Auto" }
                $tc   = if ($obj.threadCount -and [int]$obj.threadCount -gt 0) { [int]$obj.threadCount } else { [System.Environment]::ProcessorCount }

                return [pscustomobject]@{
                    RecentInputFolders = [string[]]($obj.recentInputFolders)
                    LastOutputPath     = [string]($obj.lastOutputPath)
                    LastOutputFile     = [string]($obj.lastOutputFile)
                    LastOutputMode     = $mode
                    LastTemplate       = $tpl
                    LastTheme          = $thm
                    SkipUnmodified     = [bool]($obj.skipUnmodified)
                    ThreadCount        = $tc
                    FilePath           = (Resolve-Path $SettingsPath).Path
                }
            }
        } catch {
            Write-Warning "Could not read settings at '$SettingsPath': $_."
        }
    }

    return [pscustomobject]@{
        RecentInputFolders = @()
        LastOutputPath     = ""
        LastOutputFile     = ""
        LastOutputMode     = "PerFolder"
        LastTemplate       = "default"
        LastTheme          = "Auto"
        SkipUnmodified     = $false
        ThreadCount        = [System.Environment]::ProcessorCount
        FilePath           = $SettingsPath
    }
}

function Save-SrmSettings {
    <#
    .SYNOPSIS
    Saves application settings and recent folder history to disk.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Settings,

        [Parameter(Mandatory = $false)]
        [string]$SettingsPath
    )

    $targetPath = if (![string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath } else { $Settings.FilePath }
    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        $targetPath = Join-Path $PSScriptRoot ".srm_settings.json"
    }

    $exportObj = [ordered]@{
        recentInputFolders = @($Settings.RecentInputFolders | Select-Object -Unique | Select-Object -First 15)
        lastOutputPath     = [string]$Settings.LastOutputPath
        lastOutputFile     = [string]$Settings.LastOutputFile
        lastOutputMode     = [string]$Settings.LastOutputMode
        lastTemplate       = [string]$Settings.LastTemplate
        lastTheme          = [string]$Settings.LastTheme
        skipUnmodified     = [bool]$Settings.SkipUnmodified
        threadCount        = [int]$Settings.ThreadCount
        updatedAt          = (Get-Date).ToString("o")
    }

    if ($PSCmdlet.ShouldProcess($targetPath, "Save application settings")) {
        $dir = Split-Path $targetPath -Parent
        if (![string]::IsNullOrWhiteSpace($dir) -and !(Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $exportObj | ConvertTo-Json -Depth 5 | Set-Content -Path $targetPath -Encoding UTF8
    }
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

function New-SrmShortcut {
    <#
    .SYNOPSIS
    Creates a Windows .lnk shortcut for an executable file named '<executable baseName> - Shortcut.lnk'.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ExecutablePath,

        [Parameter(Mandatory = $false, Position = 1)]
        [string]$DestinationFolder,

        [Parameter(Mandatory = $false)]
        [string]$Arguments = '',

        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = '',

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    if (!(Test-Path $ExecutablePath -PathType Leaf)) {
        Write-Error "Executable file not found: $ExecutablePath"
        return $null
    }

    $exeItem = Get-Item $ExecutablePath
    $baseName = $exeItem.BaseName
    $shortcutFileName = "$baseName - Shortcut.lnk"

    $destDir = if (![string]::IsNullOrWhiteSpace($DestinationFolder)) {
        $DestinationFolder
    } else {
        $exeItem.DirectoryName
    }

    if (!(Test-Path $destDir)) {
        if ($PSCmdlet.ShouldProcess($destDir, "Create shortcut destination directory")) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
    }

    $shortcutFullPath = Join-Path $destDir $shortcutFileName
    $workDir = if (![string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory
    } else {
        $exeItem.DirectoryName
    }

    if ($PSCmdlet.ShouldProcess($shortcutFullPath, "Create shortcut for $($exeItem.Name)")) {
        $wsh = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $wsh.CreateShortcut($shortcutFullPath)
            $shortcut.TargetPath = $exeItem.FullName
            $shortcut.WorkingDirectory = $workDir
            if (![string]::IsNullOrWhiteSpace($Arguments)) {
                $shortcut.Arguments = $Arguments
            }
            $shortcut.Save()
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
        }
    }

    return $shortcutFullPath
}

function Add-SrmManualShortcut {
    <#
    .SYNOPSIS
    Manually parses an existing .lnk shortcut OR creates a .lnk shortcut for an .exe file (named '<baseName> - Shortcut.lnk') and scans it into a manifest entry.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$FilePath,

        [Parameter(Mandatory = $false, Position = 1)]
        [string]$DestinationFolder,

        [Parameter(Mandatory = $false)]
        [object]$Database,

        [Parameter(Mandatory = $false)]
        [object]$Template
    )

    if (!(Test-Path $FilePath -PathType Leaf)) {
        Write-Error "File not found: $FilePath"
        return $null
    }

    $fileItem = Get-Item $FilePath
    $lnkPath = $null

    if ($fileItem.Extension -ieq '.lnk') {
        $lnkPath = $fileItem.FullName
    }
    elseif ($fileItem.Extension -ieq '.exe') {
        $dest = if (![string]::IsNullOrWhiteSpace($DestinationFolder)) { $DestinationFolder } else { $fileItem.DirectoryName }
        $lnkPath = New-SrmShortcut -ExecutablePath $fileItem.FullName -DestinationFolder $dest
        if ($null -eq $lnkPath -or !(Test-Path $lnkPath)) {
            Write-Error "Failed to create shortcut for: $FilePath"
            return $null
        }
    }
    else {
        Write-Error "Unsupported file type: $($fileItem.Extension). File must be .lnk or .exe."
        return $null
    }

    $shortcutInfo = ConvertFrom-LnkShortcut -Path $lnkPath
    if ($null -eq $shortcutInfo) {
        Write-Error "Failed to parse shortcut: $lnkPath"
        return $null
    }

    $hash = Get-SrmItemHash -Target $shortcutInfo.Target -StartIn $shortcutInfo.StartIn
    $lnkItem = Get-Item $lnkPath

    if ($null -ne $Database -and $null -ne $Database.Shortcuts) {
        $Database.Shortcuts[$lnkPath] = [pscustomobject]@{
            shortcutPath           = $lnkPath
            fileLastWriteTimeUtc   = $lnkItem.LastWriteTimeUtc.ToString("o")
            fileLength             = $lnkItem.Length
            title                  = $shortcutInfo.Title
            target                 = $shortcutInfo.Target
            startIn                = $shortcutInfo.StartIn
            launchOptions          = $shortcutInfo.LaunchOptions
            appendArgsToExecutable = $false
            itemHash               = $hash
            scannedAt              = (Get-Date).ToString("o")
        }
    }

    $entry = New-SrmManifestEntry `
        -Title $shortcutInfo.Title `
        -Target $shortcutInfo.Target `
        -StartIn $shortcutInfo.StartIn `
        -LaunchOptions $shortcutInfo.LaunchOptions `
        -AppendArgsToExecutable $false `
        -Template $Template `
        -SourceDirectory $lnkItem.DirectoryName `
        -ItemHash $hash

    return $entry
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
        [object]$Template,

        [Parameter(Mandatory = $false)]
        [string]$SourceDirectory = '',

        [Parameter(Mandatory = $false)]
        [string]$ItemHash = ''
    )

    $entry = [ordered]@{}

    if ($null -eq $Template) {
        $entry['title']                  = $Title
        $entry['target']                 = $Target
        $entry['startIn']                = $StartIn
        $entry['launchOptions']          = $LaunchOptions
        $entry['appendArgsToExecutable'] = $AppendArgsToExecutable
    }
    else {
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

        if (-not $entry.Contains('title')) { $entry['title'] = $Title }
        if (-not $entry.Contains('target')) { $entry['target'] = $Target }
        if (-not $entry.Contains('startIn')) { $entry['startIn'] = $StartIn }
        if (-not $entry.Contains('launchOptions')) { $entry['launchOptions'] = $LaunchOptions }
        if (-not $entry.Contains('appendArgsToExecutable')) { $entry['appendArgsToExecutable'] = $AppendArgsToExecutable }
    }

    # Attach internal metadata (stripped upon final export)
    if (![string]::IsNullOrWhiteSpace($SourceDirectory)) {
        $entry['_SourceDirectory'] = $SourceDirectory
    }
    if (![string]::IsNullOrWhiteSpace($ItemHash)) {
        $entry['_ItemHash'] = $ItemHash
    }

    return $entry
}

function Invoke-SrmParallelScan {
    <#
    .SYNOPSIS
    Scans multiple directories or shortcut files in parallel, utilizing database caching and hashing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]$InputPaths,

        [Parameter(Mandatory = $false)]
        [object]$Database,

        [Parameter(Mandatory = $false)]
        [object]$Template,

        [Parameter(Mandatory = $false)]
        [switch]$SkipUnmodified,

        [Parameter(Mandatory = $false)]
        [int]$ThreadCount = 4,

        [Parameter(Mandatory = $false)]
        [scriptblock]$OnProgress,

        [Parameter(Mandatory = $false)]
        [scriptblock]$OnLog
    )

    function Write-ScanLog([string]$level, [string]$msg) {
        if ($OnLog) {
            try { $OnLog.Invoke($level, $msg) } catch {}
        } else {
            $color = switch ($level) {
                'ERROR'   { 'Red' }
                'WARN'    { 'Yellow' }
                'SUCCESS' { 'Green' }
                'CACHE'   { 'DarkCyan' }
                'SCAN'    { 'Cyan' }
                default   { 'Gray' }
            }
            Write-Host "[$level] $msg" -ForegroundColor $color
        }
    }

    # Resolve all shortcut files from all input paths
    $files = @()
    foreach ($path in $InputPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (!(Test-Path $path)) {
            Write-ScanLog 'WARN' "Path does not exist: $path"
            continue
        }
        $resolved = (Resolve-Path $path).Path
        if (Test-Path $resolved -PathType Leaf) {
            if ($resolved -match '\.lnk$') {
                $files += Get-Item $resolved
            } else {
                Write-ScanLog 'WARN' "Skipping non-shortcut file: $resolved"
            }
        } else {
            $found = @(Get-ChildItem -Path $resolved -Filter "*.lnk" -File)
            Write-ScanLog 'INFO' "Found $($found.Count) shortcut(s) in: $resolved"
            $files += $found
        }
    }

    if ($files.Count -eq 0) {
        Write-ScanLog 'WARN' "No .lnk shortcut files found in specified paths."
        return @()
    }

    $total = $files.Count
    $results = @()
    $filesToParse = @()
    $cachedCount = 0
    $skippedCount = 0

    # 1. Fast cache check against database
    foreach ($file in $files) {
        $fullPath = $file.FullName
        $lastWrite = $file.LastWriteTimeUtc.ToString("o")
        $len = $file.Length
        $srcDir = $file.DirectoryName

        $isCachedAndUnmodified = $false
        $cachedRecord = $null

        if ($null -ne $Database -and $Database.Shortcuts -and $Database.Shortcuts.ContainsKey($fullPath)) {
            $rec = $Database.Shortcuts[$fullPath]
            if ($rec.fileLastWriteTimeUtc -eq $lastWrite -and $rec.fileLength -eq $len) {
                $isCachedAndUnmodified = $true
                $cachedRecord = $rec
            }
        }

        if ($isCachedAndUnmodified) {
            $hash = if ($cachedRecord.itemHash) { $cachedRecord.itemHash } else { Get-SrmItemHash -Target $cachedRecord.target -StartIn $cachedRecord.startIn }
            
            if ($SkipUnmodified) {
                $skippedCount++
                Write-ScanLog 'CACHE' "Unmodified shortcut skipped: $($file.Name) (hash: $($hash.Substring(0, 8))...)"
                continue
            }

            $cachedCount++
            Write-ScanLog 'CACHE' "Loaded from cache: $($file.Name) (hash: $($hash.Substring(0, 8))...)"
            
            $entry = New-SrmManifestEntry `
                -Title $cachedRecord.title `
                -Target $cachedRecord.target `
                -StartIn $cachedRecord.startIn `
                -LaunchOptions $cachedRecord.launchOptions `
                -AppendArgsToExecutable ([bool]$cachedRecord.appendArgsToExecutable) `
                -Template $Template `
                -SourceDirectory $srcDir `
                -ItemHash $hash

            $results += $entry
        } else {
            $filesToParse += $file
        }
    }

    Write-ScanLog 'INFO' "Cache evaluation: $cachedCount cached, $skippedCount skipped, $($filesToParse.Count) to parse."

    # 2. Parse new / modified files (Threaded)
    if ($filesToParse.Count -gt 0) {
        $effectiveThreads = [Math]::Max(1, [Math]::Min($ThreadCount, $filesToParse.Count))
        Write-ScanLog 'INFO' "Parsing $($filesToParse.Count) shortcut(s) using $effectiveThreads worker thread(s)..."

        if ($effectiveThreads -eq 1 -or $filesToParse.Count -eq 1) {
            # Single-threaded fallback
            $idx = 0
            foreach ($file in $filesToParse) {
                $idx++
                if ($OnProgress) {
                    try { $OnProgress.Invoke($idx, $filesToParse.Count, $file.Name, "Parsing: $($file.Name)") } catch {}
                }
                $shortcutInfo = ConvertFrom-LnkShortcut -Path $file.FullName
                if ($null -eq $shortcutInfo) {
                    Write-ScanLog 'ERROR' "Failed to parse shortcut: $($file.FullName)"
                    continue
                }

                $hash = Get-SrmItemHash -Target $shortcutInfo.Target -StartIn $shortcutInfo.StartIn

                # Update database
                if ($null -ne $Database) {
                    $Database.Shortcuts[$file.FullName] = [pscustomobject]@{
                        shortcutPath           = $file.FullName
                        fileLastWriteTimeUtc   = $file.LastWriteTimeUtc.ToString("o")
                        fileLength             = $file.Length
                        title                  = $shortcutInfo.Title
                        target                 = $shortcutInfo.Target
                        startIn                = $shortcutInfo.StartIn
                        launchOptions          = $shortcutInfo.LaunchOptions
                        appendArgsToExecutable = $false
                        itemHash               = $hash
                        scannedAt              = (Get-Date).ToString("o")
                    }
                }

                Write-ScanLog 'SCAN' "Parsed: $($file.Name) -> Target: $($shortcutInfo.Target) (hash: $($hash.Substring(0, 8))...)"

                $entry = New-SrmManifestEntry `
                    -Title $shortcutInfo.Title `
                    -Target $shortcutInfo.Target `
                    -StartIn $shortcutInfo.StartIn `
                    -LaunchOptions $shortcutInfo.LaunchOptions `
                    -AppendArgsToExecutable $false `
                    -Template $Template `
                    -SourceDirectory $file.DirectoryName `
                    -ItemHash $hash

                $results += $entry
            }
        }
        else {
            # Multi-threaded using RunspacePool with STA
            $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $effectiveThreads)
            $pool.ApartmentState = [System.Threading.ApartmentState]::STA
            $pool.Open()

            $jobs = @()
            foreach ($file in $filesToParse) {
                $ps = [System.Management.Automation.PowerShell]::Create().AddScript({
                    param($filePath, $baseName)
                    $wsh = New-Object -ComObject WScript.Shell
                    try {
                        $sc = $wsh.CreateShortcut($filePath)
                        $cleanTitle = $baseName -replace '\s*-?\s*Shortcut\s*$', ''
                        $cleanTitle = $cleanTitle -replace '\.[^.]+$', ''
                        return [pscustomobject]@{
                            Success       = $true
                            Path          = $filePath
                            Title         = $cleanTitle
                            Target        = [string]$sc.TargetPath
                            StartIn       = [string]$sc.WorkingDirectory
                            LaunchOptions = [string]$sc.Arguments
                        }
                    } catch {
                        return [pscustomobject]@{
                            Success = $false
                            Path    = $filePath
                            Error   = $_.ToString()
                        }
                    } finally {
                        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
                    }
                }).AddArgument($file.FullName).AddArgument($file.BaseName)

                $ps.RunspacePool = $pool
                $jobs += [pscustomobject]@{
                    PowerShell = $ps
                    Handle     = $ps.BeginInvoke()
                    File       = $file
                }
            }

            $completed = 0
            foreach ($job in $jobs) {
                $completed++
                $file = $job.File
                if ($OnProgress) {
                    try { $OnProgress.Invoke($completed, $jobs.Count, $file.Name, "Processed ($completed of $($jobs.Count))") } catch {}
                }

                $parseResult = $job.PowerShell.EndInvoke($job.Handle)
                $job.PowerShell.Dispose()

                if ($parseResult -and $parseResult.Success) {
                    $hash = Get-SrmItemHash -Target $parseResult.Target -StartIn $parseResult.StartIn

                    if ($null -ne $Database) {
                        $Database.Shortcuts[$file.FullName] = [pscustomobject]@{
                            shortcutPath           = $file.FullName
                            fileLastWriteTimeUtc   = $file.LastWriteTimeUtc.ToString("o")
                            fileLength             = $file.Length
                            title                  = $parseResult.Title
                            target                 = $parseResult.Target
                            startIn                = $parseResult.StartIn
                            launchOptions          = $parseResult.LaunchOptions
                            appendArgsToExecutable = $false
                            itemHash               = $hash
                            scannedAt              = (Get-Date).ToString("o")
                        }
                    }

                    Write-ScanLog 'SCAN' "Parsed: $($file.Name) -> Target: $($parseResult.Target) (hash: $($hash.Substring(0, 8))...)"

                    $entry = New-SrmManifestEntry `
                        -Title $parseResult.Title `
                        -Target $parseResult.Target `
                        -StartIn $parseResult.StartIn `
                        -LaunchOptions $parseResult.LaunchOptions `
                        -AppendArgsToExecutable $false `
                        -Template $Template `
                        -SourceDirectory $file.DirectoryName `
                        -ItemHash $hash

                    $results += $entry
                } else {
                    Write-ScanLog 'ERROR' "Failed to parse $($file.Name): $($parseResult.Error)"
                }
            }

            $pool.Close()
            $pool.Dispose()
        }
    }

    Write-ScanLog 'SUCCESS' "Scan finished: $($results.Count) manifest entries ready."
    return ,$results
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

function Clean-SrmManifestForExport {
    <#
    .SYNOPSIS
    Removes internal module metadata keys (e.g. _SourceDirectory, _ItemHash) prior to JSON serialization.
    #>
    param([object]$Entry)

    $clean = [ordered]@{}
    $props = if ($Entry -is [System.Collections.IDictionary]) {
        $Entry.Keys
    } else {
        $Entry.PSObject.Properties.Name
    }

    foreach ($k in $props) {
        if ($k -notmatch '^_') {
            $clean[$k] = if ($Entry -is [System.Collections.IDictionary]) { $Entry[$k] } else { $Entry.$k }
        }
    }
    return $clean
}

function Export-SrmManifest {
    <#
    .SYNOPSIS
    Saves an array of manifest entries as formatted JSON manifest file(s), supporting Merged, Individual (PerGame), and PerFolder output modes.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Manifests,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Merged', 'Individual', 'PerFolder', 'PerGame', 'SingleFile')]
        [string]$OutputMode = 'PerFolder',

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

    # Normalize mode names
    $normalizedMode = switch ($OutputMode) {
        'PerGame'    { 'Individual' }
        'SingleFile' { 'Merged' }
        default      { $OutputMode }
    }

    $writtenFiles = @()

    # 1. Individual (Per-Game) mode
    if ($normalizedMode -eq 'Individual') {
        if (!(Test-Path $Path)) {
            if ($PSCmdlet.ShouldProcess($Path, "Create output directory")) {
                New-Item -ItemType Directory -Force -Path $Path | Out-Null
            }
        }

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
                $cleanObj = Clean-SrmManifestForExport -Entry $entry
                ConvertTo-Json -InputObject $cleanObj -Depth 10 | Set-Content -Path $individualFilePath -Encoding UTF8
                Write-Host "-> Generated individual manifest: $individualFilePath"
                $writtenFiles += $individualFilePath
            }
        }

        if ($PassThru) { return ,$writtenFiles }
        return
    }

    # 2. PerFolder mode: collate manifest per source folder
    if ($normalizedMode -eq 'PerFolder') {
        if (!(Test-Path $Path)) {
            if ($PSCmdlet.ShouldProcess($Path, "Create output directory")) {
                New-Item -ItemType Directory -Force -Path $Path | Out-Null
            }
        }

        # Group entries by _SourceDirectory
        $groups = $Manifests | Group-Object -Property {
            if ($_.Contains('_SourceDirectory') -and !([string]::IsNullOrWhiteSpace($_['_SourceDirectory']))) {
                $_['_SourceDirectory']
            } elseif ($_.PSObject -and $_.PSObject.Properties['_SourceDirectory']) {
                $_.PSObject.Properties['_SourceDirectory'].Value
            } else {
                "General"
            }
        }

        foreach ($grp in $groups) {
            $folderPath = $grp.Name
            $folderManifestName = if ($folderPath -ne "General" -and (Test-Path $folderPath)) {
                Get-SrmDefaultManifestFileName -Path $folderPath
            } else {
                "collated.manifest.json"
            }

            $targetManifestPath = Join-Path $Path $folderManifestName
            $cleanEntries = @($grp.Group | ForEach-Object { Clean-SrmManifestForExport -Entry $_ })

            # Export this folder's collated manifest
            $res = Export-SrmManifest -Manifests $cleanEntries -Path $targetManifestPath -OutputMode 'Merged' -Append:$Append -Force:$Force -PassThru:$true
            if ($res) { $writtenFiles += $targetManifestPath }
        }

        if ($PassThru) { return ,$writtenFiles }
        return
    }

    # 3. Merged (Single File) mode
    $outputExists = Test-Path $Path -PathType Leaf
    $finalEntries = @()
    $existingTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($Append -and $outputExists) {
        $existingEntries = Import-SrmManifest -Path $Path
        foreach ($entry in $existingEntries) {
            $key = Get-SrmTargetKey $entry
            if ($null -ne $key) { [void]$existingTargets.Add($key) }
            $finalEntries += (Clean-SrmManifestForExport -Entry $entry)
        }

        foreach ($newEntry in $Manifests) {
            $key = Get-SrmTargetKey $newEntry
            if ($null -ne $key -and $existingTargets.Contains($key)) {
                Write-Host "Skipping target already present in output: $key"
                continue
            }
            if ($null -ne $key) { [void]$existingTargets.Add($key) }
            $finalEntries += (Clean-SrmManifestForExport -Entry $newEntry)
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
            $finalEntries += (Clean-SrmManifestForExport -Entry $entry)
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
        $writtenFiles += $Path
    }

    if ($PassThru) {
        return ,$writtenFiles
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
            InputPaths  = @($jsonPath)
            OutputPath  = $outPath
            EditMode    = $true
            TUI         = $tui
            Interactive = $interactive
            OutputMode  = 'Merged'
            Template    = 'default'
        }
    }

    Write-Host "`n-- Shortcut Parsing Mode --" -ForegroundColor Yellow
    $folders = @()
    while ($true) {
        $prompt = if ($folders.Count -eq 0) { "Enter path to folder containing .lnk shortcuts (or a single .lnk)" } else { "Add another folder (or press Enter to finish)" }
        $inPath = (Read-Host $prompt).Trim().Trim('"').Trim("'")
        if ([string]::IsNullOrWhiteSpace($inPath)) {
            if ($folders.Count -gt 0) { break }
            continue
        }
        if (!(Test-Path $inPath)) {
            Write-Warning "Path '$inPath' does not exist."
            continue
        }
        $folders += (Resolve-Path $inPath).Path
        Write-Host "  -> Added: $inPath" -ForegroundColor Green
    }

    $defaultOut = if (Test-Path $folders[0] -PathType Leaf) { Split-Path $folders[0] } else { $folders[0] }
    $outDir = (Read-Host "Output directory [default: $defaultOut]").Trim().Trim('"').Trim("'")
    if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = $defaultOut }

    Write-Host "`nOutput Mode:" -ForegroundColor Yellow
    Write-Host "  [1] Per Folder (collated manifest per input directory)"
    Write-Host "  [2] Per Game (individual manifest per shortcut)"
    Write-Host "  [3] Single Merged manifest file (collates all games into one file)"
    $outModeChoice = (Read-Host "Choice [1/2/3, default: 1]").Trim()
    $outMode = switch ($outModeChoice) {
        "2" { 'PerGame' }
        "3" { 'Merged' }
        default { 'PerFolder' }
    }

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
        InputPaths  = $folders
        OutputPath  = $outDir
        EditMode    = $false
        OutputMode  = $outMode
        Template    = $template
        TUI         = $tui
        Interactive = $interactive
    }
}

Export-ModuleMember -Function @(
    'Get-SrmItemHash',
    'Get-SrmTargetKey',
    'Get-SrmDefaultManifestFileName',
    'Get-SrmDatabase',
    'Save-SrmDatabase',
    'Get-SrmSettings',
    'Save-SrmSettings',
    'Get-SrmTemplate',
    'ConvertFrom-LnkShortcut',
    'New-SrmShortcut',
    'Add-SrmManualShortcut',
    'New-SrmManifestEntry',
    'Invoke-SrmParallelScan',
    'Import-SrmManifest',
    'Export-SrmManifest',
    'Read-SrmHostPrefilled',
    'Invoke-SrmInteractivePrompt',
    'Invoke-SrmTui',
    'Invoke-SrmWizard'
)
