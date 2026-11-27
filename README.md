# Steam ROM Manager - Manifest Generator & Shortcut Importer

A high-performance, multi-threaded PowerShell tool and module that parses Windows shortcuts (`.lnk`) across one or multiple folders and generates structured JSON manifests for [Steam ROM Manager](https://steamrommanager.github.io/) (SRM). It extracts executable target paths, launch arguments, and working directories, caches shortcut target hashes in a local database to skip unmodified files on repeated scans, supports custom templates and recent settings, and provides a modern desktop GUI as well as CLI/TUI interfaces.

---

## Features

- **Multi-Folder Source Selection**: Scan multiple folders of shortcuts in one operation (e.g. PC Games, Emulators, Standalone ports).
- **Multi-Threaded Parallel Parsing**: Leverages an STA worker thread pool to parse hundreds of shortcuts simultaneously without UI stutter.
- **Shortcut Hash Database (`.srm_database.json`)**:
  - Automatically computes and stores a cryptographic SHA256 hash of each shortcut's `Target` executable and `StartIn` working directory.
  - Automatically recognizes unmodified shortcuts on subsequent scans to avoid slow COM parsing.
  - Optional **Skip Unmodified** mode (`-SkipUnmodified` / GUI checkbox) to process only newly added or modified shortcuts.
- **Recent Settings & History (`.srm_settings.json`)**:
  - Automatically saves and restores recently scanned folders, output paths, preferred output mode, thread count, and theme.
  - Convenient "Recent Folders" dropdown in the GUI.
- **Output Granularity**:
  - `PerFolder` *(Default)*: Generates a collated `.manifest.json` file for each input folder scanned.
  - `PerGame` / `Individual`: Generates a separate `.manifest.json` file per game.
  - `Merged` / `SingleFile`: Combines all shortcuts from all folders into a single manifest file.
- **Templating Support**:
  - `default`: Standard SRM fields (`title`, `target`, `startIn`, `launchOptions`, `appendArgsToExecutable`).
  - `artwork`: Adds Steam Grid artwork placeholders (`cover`, `icon`, `hero`, `logo`, `banner`).
  - Custom: Supply any JSON template file containing dynamic placeholders (`{{title}}`, `{{target}}`, `{{startIn}}`, `{{launchOptions}}`), or save templates directly from the GUI.
- **Desktop GUI (`srmgenPSgui.ps1`)**:
  - Native Windows WPF interface with adaptive **Auto (System) / Dark / Light** themes.
  - Multi-folder list manager (Add, Remove, Clear, Recent Folders).
  - Two-way editable `DataGrid` preview table with column headers, in-cell edit protection, and "+ Add Game" / "- Remove" controls.
  - Live progress bar tracking parallel parsing percentage.
  - Integrated **Console & Error Activity Log** with copy and clear controls.
- **Command-Line & TUI Editors (`srmgenPS.ps1`)**:
  - Interactive setup wizard when run with zero parameters.
  - Alternate-buffer console spreadsheet editor (`-TUI` / `-t`).
  - Sequential interactive editor (`-Interactive` / `-i`).
  - Direct manifest editing (`-EditMode` / `-e`).
  - Native PowerShell pipeline support (`Get-ChildItem -Directory | .\srmgenPS.ps1`).

---

## Project Structure

```
srm-generator/
├── srmgen.psd1             # Module manifest (metadata, exported cmdlets)
├── srmgen.psm1             # Core logic engine (LNK parsing, hash database, threads, export)
├── srmgenPS.ps1            # Multi-threaded CLI runner with wizard & TUI
├── srmgenPSgui.ps1         # Native WPF desktop GUI with multi-folder & log
├── TODO.md                 # Project roadmap and milestone tracker
├── templates/              # Manifest templates
│   ├── default.template.json
│   └── artwork.template.json
├── tests/
│   └── Test-SrmGen.ps1     # Automated test suite (49 tests)
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
   Launch the native desktop interface:
   ```powershell
   .\srmgenPSgui.ps1
   ```

3. **Interactive CLI Wizard** (no arguments needed):
   ```powershell
   .\srmgenPS.ps1
   ```

4. **Direct CLI Generation**:
   ```powershell
   .\srmgenPS.ps1 -InputPaths "D:\Games\Shortcuts", "D:\Emulators\Shortcuts" -OutputPath "C:\SRM\Manifests"
   ```

---

## CLI Usage & Parameter Reference

### Parameters

| Parameter | Alias | Type | Default | Description |
| :--- | :---: | :---: | :---: | :--- |
| `-InputPaths` | `-InputPath`, `-p` | String[] | *Wizard* | Path(s) to directory/directories containing `.lnk` files (or a single `.lnk` / `.json` manifest). Accepts multiple folders. |
| `-OutputPath` | `-o` | String | Input dir | Directory where generated manifest file(s) will be saved. |
| `-OutputMode` | `-m` | String | `PerFolder` | `PerFolder` (manifest per input directory), `PerGame` (individual file per game), or `Merged` (single combined manifest). |
| `-OutputFile` | | String | `<Drive>_<Folder>.manifest.json` | Custom output filename (for `Merged` mode). |
| `-Template` | | String | `default` | Manifest template: `default`, `artwork`, or path to a custom JSON template file. |
| `-SkipUnmodified`| | Switch | `$false` | Skip shortcuts whose file timestamp and hash match an existing database record. |
| `-NoCache` | | Switch | `$false` | Disables database caching and forces fresh parsing of all shortcuts. |
| `-Threads` | | Int | CPU count | Number of worker threads for parallel shortcut scanning. |
| `-Append` | `-a` | Switch | `$false` | Appends new entries to existing manifest(s), skipping duplicate targets. |
| `-Force` | | Switch | `$false` | Overwrites existing output manifest(s) without confirmation prompts. |
| `-Interactive`| `-i` | Switch | `$false` | Interactively prompts for and updates fields for each shortcut sequentially. |
| `-TUI` | `-t` | Switch | `$false` | Opens a full-screen console spreadsheet table to inspect and edit rows. |
| `-EditMode` | `-e` | Switch | `$false` | Modifies an existing `.manifest.json` file rather than parsing shortcuts. |
| `-WhatIf` | | Switch | | Dry-run preview of intended file actions. |

---

### CLI Examples

#### 1. Scan Multiple Folders (Collated per Folder)
```powershell
.\srmgenPS.ps1 -InputPaths "D:\Shortcuts\PC Games", "D:\Shortcuts\Emulators" -OutputPath "D:\SRM\Manifests"
```
*Generates `D_PC Games.manifest.json` and `D_Emulators.manifest.json` in `D:\SRM\Manifests`.*

#### 2. Fast Incremental Scan (Skip Unmodified)
```powershell
.\srmgenPS.ps1 -InputPaths "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests" -SkipUnmodified
```
*Checks `.srm_database.json`: any shortcut whose executable path and working directory have not changed is skipped.*

#### 3. Output as Individual Files (One per Game)
```powershell
.\srmgenPS.ps1 -InputPaths "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests" -OutputMode PerGame
```

#### 4. Single Merged Manifest with Custom Name
```powershell
.\srmgenPS.ps1 -InputPaths "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests" -OutputMode Merged -OutputFile "AllGames.json"
```

#### 5. Parallel Processing with Custom Thread Count
```powershell
.\srmgenPS.ps1 -InputPaths "D:\Shortcuts\LargeLibrary" -OutputPath "D:\SRM\Manifests" -Threads 8
```

#### 6. Interactive Spreadsheet TUI
```powershell
.\srmgenPS.ps1 -InputPaths "D:\Shortcuts\PC Games" -OutputPath "D:\SRM\Manifests" -TUI
```

---

## Shortcut Database & Hash Caching

When shortcuts are parsed, `srm-generator` creates or updates a local database (`.srm_database.json`):
- **Hash Algorithm**: SHA-256 of `$Target|$StartIn` (lowercased and normalized).
- **Metadata Recorded**: Shortcut path, file last write timestamp, file byte length, parsed title, target executable, working directory, launch arguments, and composite item hash.
- **Performance**:
  - Scanning 1,000 shortcuts for the first time parses in parallel across multiple worker threads.
  - Scanning the same folder again instantly verifies file timestamps and loads all entries from cache in milliseconds without COM overhead.
  - When `-SkipUnmodified` is enabled, unchanged shortcuts bypass output processing entirely.

---

## Configuring Steam ROM Manager (SRM)

1. Open **Steam ROM Manager**.
2. Navigate to **Parsers** in the left sidebar.
3. Select **Manual** or a Community Preset.
4. Configure parser settings:
   - **Parser type**: `Manual`
   - **Manifests directory / path**:
     - If using `PerFolder` or `Merged`: point to the generated `.manifest.json` file.
     - If using `PerGame`: point to the output folder containing the individual `.manifest.json` files.
   - **Steam category**: Set a category name (e.g. `Non-Steam PC Games`).
5. Click **Save** $\rightarrow$ go to **Preview** $\rightarrow$ click **Generate app list** $\rightarrow$ **Save to Steam**.

---

## Running Automated Tests

Run the full automated test suite (49 unit and integration tests):

```powershell
powershell -File .\tests\Test-SrmGen.ps1
```

---

## License

MIT License. See LICENSE file for details.
