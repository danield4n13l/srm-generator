#
# Unit and integration test suite for srmgen module
#
$scriptDir = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $scriptDir "srmgen.psd1") -Force

$passed = 0
$failed = 0

function Assert-Equal {
    param(
        [string]$TestName,
        [object]$Actual,
        [object]$Expected
    )
    if ($Actual -eq $Expected) {
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        Write-Host "         Expected: '$Expected'" -ForegroundColor Yellow
        Write-Host "         Actual:   '$Actual'" -ForegroundColor Yellow
        $script:failed++
    }
}

function Assert-True {
    param(
        [string]$TestName,
        [bool]$Condition
    )
    if ($Condition) {
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $TestName (Condition was false)" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Running srmgen Test Suite" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Shortcut parsing tests
Write-Host "`n1. ConvertFrom-LnkShortcut" -ForegroundColor White
$animalWellShortcut = Join-Path $scriptDir "TEST\Animal Well.exe - Shortcut.lnk"
$animalWell = ConvertFrom-LnkShortcut -Path $animalWellShortcut
Assert-Equal "Title stripped correctly" $animalWell.Title "Animal Well"
Assert-True "Target points to .exe" ($animalWell.Target -like "*Animal Well.exe")
Assert-True "StartIn points to game folder" ($animalWell.StartIn -like "*Animal Well")

$bipedShortcut = Join-Path $scriptDir "TEST\Biped2.exe - Shortcut.lnk"
$biped = ConvertFrom-LnkShortcut -Path $bipedShortcut
Assert-Equal "Title parsed correctly" $biped.Title "Biped2"
Assert-True "Target parsed correctly" ($biped.Target -like "*Biped2.exe")

# 2. Manifest entry creation (default)
Write-Host "`n2. New-SrmManifestEntry" -ForegroundColor White
$entry = New-SrmManifestEntry -Title "My Game" -Target "D:\Games\MyGame.exe" -StartIn "D:\Games" -LaunchOptions "-windowed"
Assert-Equal "Entry title" $entry.title "My Game"
Assert-Equal "Entry target" $entry.target "D:\Games\MyGame.exe"
Assert-Equal "Entry startIn" $entry.startIn "D:\Games"
Assert-Equal "Entry launchOptions" $entry.launchOptions "-windowed"
Assert-Equal "Entry appendArgs" $entry.appendArgsToExecutable $false

# 3. Templating Support
Write-Host "`n3. Get-SrmTemplate & Templated Entries" -ForegroundColor White
$defaultTpl = Get-SrmTemplate -Template "default"
Assert-True "Default template has title" ($defaultTpl.Contains("title"))
Assert-True "Default template has target" ($defaultTpl.Contains("target"))

$artworkTpl = Get-SrmTemplate -Template "artwork"
Assert-True "Artwork template has cover" ($artworkTpl.Contains("cover"))
Assert-True "Artwork template has hero" ($artworkTpl.Contains("hero"))

$templatedEntry = New-SrmManifestEntry -Title "Templated Game" -Target "C:\Game\game.exe" -StartIn "C:\Game" -Template $artworkTpl
Assert-Equal "Templated title substituted" $templatedEntry.title "Templated Game"
Assert-Equal "Templated target substituted" $templatedEntry.target "C:\Game\game.exe"
Assert-True "Templated entry retains cover key" ($templatedEntry.Contains("cover"))

# 4. Target key extraction & trimming
Write-Host "`n4. Get-SrmTargetKey" -ForegroundColor White
$testObj = @{ target = "   C:\Path\Game.exe   " }
Assert-Equal "Trims whitespace" (Get-SrmTargetKey $testObj) "C:\Path\Game.exe"
$emptyObj = @{ target = "   " }
Assert-Equal "Returns null for empty target" (Get-SrmTargetKey $emptyObj) $null

# 5. Default filename calculation
Write-Host "`n5. Get-SrmDefaultManifestFileName" -ForegroundColor White
$fn = Get-SrmDefaultManifestFileName -Path (Join-Path $scriptDir "TEST")
Assert-Equal "Matches expected drive_folder naming" $fn "D_TEST.manifest.json"

# 6. Manifest export, import, append and deduplication (Merged mode)
Write-Host "`n6. Export-SrmManifest (Merged) & Import-SrmManifest" -ForegroundColor White
$tempDir = Join-Path $env:TEMP "srmgen_test_$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$testManifestPath = Join-Path $tempDir "test.manifest.json"

try {
    $initialEntries = @(
        (New-SrmManifestEntry -Title "Game A" -Target "C:\Games\A.exe"),
        (New-SrmManifestEntry -Title "Game B" -Target "C:\Games\B.exe")
    )

    Export-SrmManifest -Manifests $initialEntries -Path $testManifestPath -Force
    Assert-True "Manifest file created" (Test-Path $testManifestPath)

    $imported = Import-SrmManifest -Path $testManifestPath
    Assert-Equal "Imported count" $imported.Count 2
    Assert-Equal "First entry title" $imported[0].title "Game A"
    Assert-Equal "Second entry title" $imported[1].title "Game B"

    # Append entries (including 1 duplicate target)
    $appendEntries = @(
        (New-SrmManifestEntry -Title "Game A Dup" -Target "C:\Games\A.exe"),
        (New-SrmManifestEntry -Title "Game C" -Target "C:\Games\C.exe")
    )

    Export-SrmManifest -Manifests $appendEntries -Path $testManifestPath -Append
    $importedAfter = Import-SrmManifest -Path $testManifestPath
    Assert-Equal "Appended count deduplicated" $importedAfter.Count 3
    Assert-Equal "Third entry title" $importedAfter[2].title "Game C"
}
finally {
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
}

# 7. Manifest export (Individual mode)
Write-Host "`n7. Export-SrmManifest (Individual Mode)" -ForegroundColor White
$tempIndivDir = Join-Path $env:TEMP "srmgen_indiv_test_$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempIndivDir -Force | Out-Null

try {
    $indivEntries = @(
        (New-SrmManifestEntry -Title "Game Alpha" -Target "C:\Games\Alpha.exe"),
        (New-SrmManifestEntry -Title "Game Beta" -Target "C:\Games\Beta.exe")
    )

    Export-SrmManifest -Manifests $indivEntries -Path $tempIndivDir -OutputMode "Individual" -Force
    $alphaFile = Join-Path $tempIndivDir "Game Alpha.manifest.json"
    $betaFile = Join-Path $tempIndivDir "Game Beta.manifest.json"

    Assert-True "Game Alpha individual file exists" (Test-Path $alphaFile)
    Assert-True "Game Beta individual file exists" (Test-Path $betaFile)

    $alphaContent = Get-Content $alphaFile -Raw | ConvertFrom-Json
    Assert-Equal "Alpha title matches" $alphaContent.title "Game Alpha"
}
finally {
    Remove-Item -Recurse -Force $tempIndivDir -ErrorAction SilentlyContinue
}

# 8. Pipeline processing test
Write-Host "`n8. Pipeline processing" -ForegroundColor White
$piped = Get-ChildItem (Join-Path $scriptDir "TEST") -Filter "*.lnk" | ConvertFrom-LnkShortcut
Assert-Equal "Pipeline parsed 3 shortcuts" $piped.Count 3

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Results: $passed Passed, $failed Failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Cyan

if ($failed -gt 0) {
    exit 1
}
