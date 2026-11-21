# Steam ROM Manager - Manifest Generator & Shortcut Importer

A PowerShell tool and module that parses Windows shortcuts (`.lnk`) and generates structured JSON manifests for [Steam ROM Manager](https://steamrommanager.github.io/) (SRM). It extracts executable target paths, launch arguments, and working directories, cleans shortcut titles, deduplicates entries, and provides interactive wizards, templating, and TUI spreadsheet editors.

---

## Features

- **Automated `.lnk` Parsing**: Reads Windows shortcuts to extract target executables, working directories (`startIn`), and launch arguments.
- **Title Normalization**: Automatically strips redundant suffixes such as ` - Shortcut` and file extensions like `.exe`.
- **Duplicate Prevention**: Intelligently deduplicates games by target executable path when appending (`-Append`) to existing manifests.
- **Templating Support**:
  - `default`: Core SRM fields (`title`, `target`, `startIn`, `launchOptions`, `appendArgsToExecutable`).
  - `artwork`: Adds Steam Grid artwork placeholders (`cover`, `icon`, `hero`, `logo`, `banner`).
  - Custom: Supply any JSON template file containing token placeholders like `{{title}}`, `{{target}}`, `{{startIn}}`, and `{{launchOptions}}`.
- **Output Granularity**:
  - `Merged`: Combines all shortcuts into a single manifest file (ideal for SRM Manual parser).
  - `Individual`: Generates an individual `.manifest.json` file per game.
- **Interactive Editing**:
  - **Setup Wizard**: Run `.\srmgenPS.ps1` with no arguments for a step-by-step guided configuration.
  - **Sequential Prompts (`-Interactive` / `-i`)**: Prompt through each shortcut's properties in the terminal.
  - **Spreadsheet TUI (`-TUI` / `-t`)**: Edit titles, targets, and launch options in a console table using an alternate screen buffer.
- **Manifest Editor (`-EditMode` / `-e`)**: Directly load, inspect, and modify an existing `.manifest.json` file without re-parsing shortcuts.
- **Safe Execution & Progress**: Supports PowerShell `-WhatIf` dry-runs, `-Force` overwrite flags, and native progress bars (`Write-Progress`).
- **Reusable Core Module**: Cleanly architected PowerShell module (`srmgen.psd1` / `srmgen.psm1`) with pipeline support for custom automation or GUI frontends.

---

## Project Structure

```
srm-generator/
├── srmgen.psd1             # Module manifest (metadata, exported cmdlets)
├── srmgen.psm1             # Core logic engine (LNK parsing, JSON export, TUI, wizard)
├── srmgenPS.ps1            # CLI runner with full argument validation and wizard
├── srmgenPSgui.ps1         # Native WPF/XAML graphical user interface
├── TODO.md                 # Project roadmap and milestone tracker
├── templates/              # Built-in and custom manifest templates
│   ├── default.template.json
│   └── artwork.template.json
├── tests/
│   └── Test-SrmGen.ps1     # Automated test suite (30 tests)
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

2. **Graphical User Interface (GUI)**:
   Launch the native desktop interface with folder pickers and interactive data grid:
   ```powershell
   .\srmgenPSgui.ps1
   ```

3. **Interactive CLI Wizard** (no arguments needed):
   ```powershell
   .\srmgenPS.ps1
   ```

4. **Direct CLI Generation**:
   ```powershell
   .\srmgenPS.ps1 -InputPath "C:\Games\Shortcuts" -OutputPath "C:\SRM\Manifests"
   ```

---

## CLI Usage & Examples

### Parameter Reference

| Parameter | Alias | Type | Default | Description |
| :--- | :---: | :---: | :---: | :--- |
| `-InputPath` | `[0]` | String | *Interactive Wizard* | Path to a directory containing `.lnk` files, a single `.lnk` file, or a `.json` manifest (in Edit mode). If omitted in an interactive terminal, launches the setup wizard. |
| `-OutputPath`| `[1]` | String | Input directory | Directory where generated manifest file(s) will be saved. |
| `-OutputFile`| | String | `<Drive>_<Folder>.manifest.json` | Custom output filename (overrides the default naming pattern in Merged mode). |
| `-OutputMode`| | String | `Merged` | `Merged` (single JSON array) or `Individual` (separate `.manifest.json` file per game). |
| `-Template` | | String | `default` | Manifest template: `default`, `artwork`, or path to a custom JSON template file. |
| `-Append` | `-a` | Switch | `$false` | Appends new entries to an existing output manifest, skipping duplicate targets. |
| `-Force` | | Switch | `$false` | Overwrites the output manifest without confirmation prompts. |
| `-Interactive`| `-i` | Switch | `$false` | Interactively prompts for and updates fields for each shortcut sequentially. |
| `-TUI` | `-t` | Switch | `$false` | Opens a full-screen console table to inspect and edit rows. |
| `-EditMode` | `-e` | Switch | `$false` | Modifies an existing `.manifest.json` file rather than parsing shortcuts. |
| `-WhatIf` | | Switch | | Simulates the operation and displays the intended file action without writing. |

---

### Examples

#### 1. Interactive Setup Wizard
Running the script without arguments starts the interactive wizard:
```powershell
.\srmgenPS.ps1
```

#### 2. Basic Generation (Merged)
Scan a directory of shortcuts and create a single merged manifest in the destination folder:
```powershell
.\srmgenPS.ps1 -InputPath "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests"
```
*Note: The generated manifest filename is formatted automatically as `<Drive>_<Folder>.manifest.json` (e.g. `D_PC Games.manifest.json`).*

#### 3. Generating Individual Manifest Files
Generate a separate manifest JSON file for each shortcut:
```powershell
.\srmgenPS.ps1 -InputPath "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests" -OutputMode Individual
```

#### 4. Custom Output Filename
Specify an explicit manifest filename:
```powershell
.\srmgenPS.ps1 -InputPath "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests" -OutputFile "NonSteamGames.json"
```

#### 5. Using the Artwork Template
Generate a manifest pre-populated with artwork fields (`cover`, `icon`, `hero`, `logo`, `banner`):
```powershell
.\srmgenPS.ps1 -InputPath "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests" -Template artwork
```

#### 6. Appending New Shortcuts Without Duplicates
Add newly acquired shortcuts to your existing manifest while automatically skipping games that are already present:
```powershell
.\srmgenPS.ps1 -InputPath "D:\Shortcuts\NewGames" -OutputPath "D:\SRM\Manifests" -Append
```

#### 7. Spreadsheet-Like TUI Editor
Parse shortcuts and immediately open the terminal editor to review and tweak game titles or add launch arguments before saving:
```powershell
.\srmgenPS.ps1 -InputPath "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests" -TUI
```

#### 8. Editing an Existing Manifest
Open an already generated manifest in the TUI editor to fix a typo or update executable paths:
```powershell
.\srmgenPS.ps1 -InputPath "D:\SRM\Manifests\D_PC Games.manifest.json" -EditMode -TUI
```

#### 9. Dry-Run Preview
Check what manifest file(s) would be created or modified without touching disk:
```powershell
.\srmgenPS.ps1 -InputPath "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests" -WhatIf
```

---

## Custom Templates

You can create a custom JSON template file and pass it via `-Template <path>`:

```json
{
  "title": "{{title}}",
  "target": "{{target}}",
  "startIn": "{{startIn}}",
  "launchOptions": "{{launchOptions}}",
  "appendArgsToExecutable": false,
  "category": "Emulators",
  "tags": ["Standalone", "PC"]
}
```

Placeholders (`{{title}}`, `{{target}}`, `{{startIn}}`, `{{launchOptions}}`) will be dynamically replaced for each parsed shortcut.

---

## Configuring Steam ROM Manager (SRM)

Once your manifest is generated, add it to Steam ROM Manager:

1. Open **Steam ROM Manager**.
2. Navigate to **Parsers** in the left sidebar.
3. Select **Manual** or a Community Preset designed for manifest-based shortcuts.
4. Configure the parser settings:
   - **Parser type**: `Manual`
   - **Manifests directory / path**: Point to your generated `.manifest.json` file (for Merged mode) or the folder containing individual manifests (for Individual mode).
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

Run the built-in test suite to verify module behavior, path resolution, templating, and deduplication:

```powershell
powershell -File .\tests\Test-SrmGen.ps1
```

---

## License

MIT License. See LICENSE file for details.
