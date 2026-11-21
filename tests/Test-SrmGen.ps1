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

# 2. Manifest entry creation
Write-Host "`n2. New-SrmManifestEntry" -ForegroundColor White
$entry = New-SrmManifestEntry -Title "My Game" -Target "D:\Games\MyGame.exe" -StartIn "D:\Games" -LaunchOptions "-windowed"
Assert-Equal "Entry title" $entry.title "My Game"
Assert-Equal "Entry target" $entry.target "D:\Games\MyGame.exe"
Assert-Equal "Entry startIn" $entry.startIn "D:\Games"
Assert-Equal "Entry launchOptions" $entry.launchOptions "-windowed"
Assert-Equal "Entry appendArgs" $entry.appendArgsToExecutable $false

# 3. Target key extraction & trimming
Write-Host "`n3. Get-SrmTargetKey" -ForegroundColor White
$testObj = @{ target = "   C:\Path\Game.exe   " }
Assert-Equal "Trims whitespace" (Get-SrmTargetKey $testObj) "C:\Path\Game.exe"
$emptyObj = @{ target = "   " }
Assert-Equal "Returns null for empty target" (Get-SrmTargetKey $emptyObj) $null

# 4. Default filename calculation
Write-Host "`n4. Get-SrmDefaultManifestFileName" -ForegroundColor White
$fn = Get-SrmDefaultManifestFileName -Path (Join-Path $scriptDir "TEST")
Assert-Equal "Matches expected drive_folder naming" $fn "D_TEST.manifest.json"

# 5. Manifest export, import, append and deduplication
Write-Host "`n5. Export-SrmManifest & Import-SrmManifest" -ForegroundColor White
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
        (New-SrmManifestEntry -Title "Game A Dup" -Target "C:\Games\A.exe"), # duplicate
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

# 6. Pipeline support test
Write-Host "`n6. Pipeline processing" -ForegroundColor White
$piped = Get-ChildItem (Join-Path $scriptDir "TEST") -Filter "*.lnk" | ConvertFrom-LnkShortcut
Assert-Equal "Pipeline parsed 3 shortcuts" $piped.Count 3

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Results: $passed Passed, $failed Failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Cyan

if ($failed -gt 0) {
    exit 1
}
