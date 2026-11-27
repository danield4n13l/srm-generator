# SRM Manifest Generator - TODO

## Phase 1: Core CLI Script & Module Architecture (High Priority)
- [x] Choose programming language and set up project structure.
- [x] Refactor core engine into a reusable PowerShell module (`srmgen.psd1` / `srmgen.psm1`).
- [x] Implement automated test suite (`tests/Test-SrmGen.ps1`).
- [x] Implement argument parsing (input directory/files, output directory, single-file output flag, etc.).
- [x] Implement `.lnk` parsing logic to extract target path, launch arguments, and icon/working directory.
- [x] Implement JSON generation based on parsed `.lnk` data (mapping shortcut properties to manifest fields).
- [x] Implement advanced templating support (custom template files, token expansion, cover/artwork fields).
- [x] Implement output granularity options (individual manifest JSON files per game vs. merged `manifest.json`).
- [x] Implement output concatenation & deduplication feature (merge shortcuts into a single manifest, skipping duplicate targets).
- [x] Write project documentation (`README.md`).

## Phase 2: Interactive CLI / TUI (Medium Priority)
- [x] Integrate console TUI editor (`-TUI`) using alternate screen buffer.
- [x] Implement sequential interactive property editor (`-Interactive`).
- [x] Implement an interactive setup wizard that guides the user through parameter selection if no CLI arguments are provided.
- [x] Add visual feedback (progress bars via `Write-Progress`) for bulk processing.

## Phase 3: GUI Wrapper (Low Priority / Optional)
- [x] Choose a lightweight GUI framework (WPF/XAML with modern dark styling).
- [x] Build an interactive form-based UI in `srmgenPSgui.ps1` with folder pickers, template selection, and an editable preview table.
- [x] Connect the GUI inputs to execute the core `srmgen` module cmdlets with live DataGrid editing and File Explorer integration.

## Phase 4: High Performance & Advanced Features (Completed)
- [x] Multi-folder scanning support across one or multiple shortcut directories.
- [x] Output granularity: PerFolder collated manifests, PerGame individual files, and Merged single files.
- [x] Shortcut manifest database (`.srm_database.json`) caching SHA-256 hash of target executable and working directory.
- [x] Incremental scan mode (`-SkipUnmodified` / GUI checkbox) to skip already scanned, unmodified shortcuts.
- [x] Persistent application settings and folder history (`.srm_settings.json`).
- [x] Multi-threaded parallel shortcut parsing via worker thread pool (`-Threads`).
- [x] Manually add shortcut feature (`New-SrmShortcut` and `Add-SrmManualShortcut`) supporting `.lnk` files and `.exe` files (generating `<baseName> - Shortcut.lnk`).
- [x] Live progress bar tracking parallel parsing percentage in CLI and GUI.
- [x] Comprehensive console and error activity log in the GUI with copy/clear controls.
- [x] Expanded automated test suite with 60 unit and integration tests.

