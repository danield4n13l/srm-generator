# SRM Manifest Generator - TODO

## Phase 1: Core CLI Script (High Priority)
- [x] Choose programming language and set up project structure.
- [x] Implement argument parsing (input directory/files, output directory, template, single-file output flag, etc.).
- [x] Implement `.lnk` parsing logic to extract target path, launch arguments, and icon/working directory.
- [x] Implement JSON generation based on parsed `.lnk` data (mapping shortcut properties to manifest fields).
- [x] Implement templating support (use a default template if none provided, allow user to specify a custom template).
- [x] Implement output logic to write individual manifest JSON files to the output directory.
- [x] Implement output concatenation feature (option to merge all generated manifests into a single `manifest.json` file).

## Phase 2: Interactive CLI / TUI (Medium Priority)
- [x] Integrate an interactive prompt library.
- [ ] Implement an interactive mode that guides the user through parameter selection (input/output paths, template choices) if no CLI arguments are provided.
- [ ] Add visual feedback (progress bars, success/error messages) for bulk processing.

## Phase 3: GUI Wrapper (Low Priority / Optional)
- [ ] Choose a lightweight GUI framework.
- [ ] Build a simple form-based UI to select input/output folders and configure templates visually.
- [ ] Connect the GUI inputs to execute the core script logic.
