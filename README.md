# Steam ROM Manager - Manifest Generator & Shortcut Importer

A PowerShell tool and module that parses Windows shortcuts (`.lnk`) and generates structured JSON manifests for [Steam ROM Manager](https://steamrommanager.github.io/) (SRM). It extracts executable target paths, launch arguments, and working directories, cleans shortcut titles, deduplicates entries, and provides interactive sequential and TUI spreadsheet editors.

---

## Features

- **Automated `.lnk` Parsing**: Reads Windows shortcuts to extract target executables, working directories (`startIn`), and launch arguments.
- **Title Normalization**: Automatically strips redundant suffixes such as ` - Shortcut` and file extensions like `.exe`.
- **Duplicate Prevention**: Intelligently deduplicates games by target executable path when appending (`-Append`) to existing manifests.
- **Interactive Editing**:
  - **Sequential Wizard (`-Interactive` / `-i`)**: Prompt through each shortcut's properties in the terminal.
  - **Spreadsheet TUI (`-TUI` / `-t`)**: Edit titles, targets, and launch options in a console table using an alternate screen buffer.
- **Manifest Editor (`-EditMode` / `-e`)**: Directly load, inspect, and modify an existing `.manifest.json` file without re-parsing shortcuts.
- **Safe Execution**: Full support for PowerShell `-WhatIf` dry-runs and `-Force` overwrite flags.
- **Reusable Core Module**: Cleanly architected PowerShell module (`srmgen.psd1` / `srmgen.psm1`) with pipeline support for custom automation or GUI frontends.

---

## Project Structure

```
srm-generator/
├── srmgen.psd1             # Module manifest (metadata, exported cmdlets)
├── srmgen.psm1             # Core logic engine (LNK parsing, JSON export, TUI)
├── srmgenPS.ps1            # CLI runner with full argument validation
├── srmgenPSgui.ps1         # Planned GUI interface (Phase 3)
├── TODO.md                 # Project roadmap and milestone tracker
├── tests/
│   └── Test-SrmGen.ps1     # Automated test suite
└── TEST/                   # Sample .lnk shortcuts and test manifests
```

---

## Requirements

- **Windows 10 / 11** or **Windows Server**
- **PowerShell 5.1** or later (Windows PowerShell or PowerShell 7+)

---

## Installation & Quick Start

1. Clone or download this repository:
   ```powershell
   git clone https://github.com/your-username/srm-generator.git
   cd srm-generator
   ```

2. Generate a manifest from a folder of shortcuts:
   ```powershell
   .\srmgenPS.ps1 -InputPath "C:\Games\Shortcuts" -OutputPath "C:\SRM\Manifests"
   ```

---

## CLI Usage & Examples

### Parameter Reference

| Parameter | Alias | Type | Description |
| :--- | :---: | :---: | :--- |
| `-InputPath` | | String | **Required.** Path to a directory containing `.lnk` files, a single `.lnk` file, or a `.json` manifest (in Edit mode). |
| `-OutputPath`| | String | Directory where the generated manifest will be saved (required when not in Edit mode). |
| `-Append` | `-a` | Switch | Appends new entries to an existing output manifest, skipping duplicate targets. |
| `-Force` | | Switch | Overwrites the output manifest without confirmation prompts. |
| `-Interactive`| `-i` | Switch | Interactively prompts for and updates fields for each shortcut sequentially. |
| `-TUI` | `-t` | Switch | Opens a full-screen console table to inspect and edit rows. |
| `-EditMode` | `-e` | Switch | Modifies an existing `.manifest.json` file rather than parsing shortcuts. |
| `-WhatIf` | | Switch | Simulates the operation and displays the intended file action without writing. |

---

### Examples

#### 1. Basic Generation
Scan a directory of shortcuts and create a manifest in the destination folder:
```powershell
.\srmgenPS.ps1 -InputPath "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests"
```
*Note: The generated manifest filename is formatted automatically as `<Drive>_<Folder>.manifest.json` (e.g. `D_PC Games.manifest.json`).*

#### 2. Appending New Shortcuts
Add newly acquired shortcuts to your existing manifest while automatically skipping games that are already present:
```powershell
.\srmgenPS.ps1 -InputPath "D:\Shortcuts\NewGames" -OutputPath "D:\SRM\Manifests" -Append
```

#### 3. Spreadsheet-Like TUI Editor
Parse shortcuts and immediately open the terminal editor to review and tweak game titles or add launch arguments before saving:
```powershell
.\srmgenPS.ps1 -InputPath "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests" -TUI
```

#### 4. Editing an Existing Manifest
Open an already generated manifest in the TUI editor to fix a typo or update executable paths:
```powershell
.\srmgenPS.ps1 -InputPath "D:\SRM\Manifests\D_PC Games.manifest.json" -EditMode -TUI
```

#### 5. Dry-Run Preview
Check what manifest file would be created or modified without touching disk:
```powershell
.\srmgenPS.ps1 -InputPath "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests" -WhatIf
```

---

## Configuring Steam ROM Manager (SRM)

Once your manifest is generated, add it to Steam ROM Manager:

1. Open **Steam ROM Manager**.
2. Navigate to **Parsers** in the left sidebar.
3. Select **Manual** or a Community Preset designed for manifest-based shortcuts.
4. Configure the parser settings:
   - **Parser type**: `Manual`
   - **Manifests directory / path**: Point to the generated `.manifest.json` file.
   - **Steam category**: Set a category name (e.g. `Non-Steam PC Games`).
5. Save the parser settings.
6. Go to **Preview**, click **Generate app list**, verify the matched titles and artwork, and click **Save to Steam**.

---

## Using the `srmgen` PowerShell Module Directly

You can import `srmgen.psd1` into custom PowerShell scripts or automated setup workflows:

```powershell
Import-Module .\srmgen.psd1 -Force

# Parse shortcuts via pipeline
Get-ChildItem "C:\MyShortcuts" -Filter *.lnk | ConvertFrom-LnkShortcut | Format-Table Title, Target, StartIn

# Programmatically build and export a manifest
$entries = @(
    New-SrmManifestEntry -Title "Hollow Knight" -Target "C:\Games\Hollow Knight\hollow_knight.exe" -StartIn "C:\Games\Hollow Knight",
    New-SrmManifestEntry -Title "Celeste" -Target "C:\Games\Celeste\Celeste.exe" -StartIn "C:\Games\Celeste"
)

Export-SrmManifest -Manifests $entries -Path "C:\SRM\manifest.json" -Force
```

---

## Running Automated Tests

Run the built-in test suite to verify module behavior, path resolution, and deduplication:

```powershell
powershell -File .\tests\Test-SrmGen.ps1
```

---

## License

MIT License. See LICENSE file for details.
