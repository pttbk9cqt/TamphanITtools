# SPEC.md

Project contract for WinUtil — what the project is, how it's built, and how it runs. Written for anyone, human or AI, who needs to understand the project itself.

`AGENTS.md` in the repository root points here for these facts, and separately covers how an agent should behave while working in this repo. This file does not change based on who's reading it.

## Project Context

WinUtil is a Windows PowerShell utility with a WPF interface. The repository is maintained as modular source, but the distributed artifact is one compiled PowerShell script.

### Stack

- Language: Windows PowerShell / PowerShell.
- UI: WPF via `xaml/inputXML.xaml`.
- Selection UI: Application has no selected-app popup; Tweaks uses All/Clear without applying immediate toggles; AppX uses Select All/Clear Selection. Maintenance completion restores its tab and window focus; Explorer restart runs in the background and targets the current Windows session.
- Configuration: JSON files under `config/`.
- Tests: Pester tests under `pester/`.
- Lint: PowerShell Script Analyzer with settings in `lint/PSScriptAnalyser.ps1`.
- Release artifact: generated root `winutil.ps1`.

### Repository Layout

- `Compile.ps1`: build script that creates `winutil.ps1`.
- `TamphanITtools.cmd`: standalone Windows PowerShell launcher with explicit online and offline modes.
- `Build-Portable.ps1`: compiles and packages local release assets into ignored `binary/`; never publishes them.
- `scripts/start.ps1`: startup/bootstrap segment used at the beginning of the compiled script.
- `scripts/main.ps1`: main entrypoint appended at the end of the compiled script.
- `functions/public/`: public/UI-facing PowerShell functions.
- `functions/private/`: internal helper PowerShell functions.
- `config/`: JSON configuration consumed at compile time and embedded into `$sync.configs`.
- `maintenance/`: the RunOriginal.ps1 adapter embedded by the compiler for the active original Maintenance workflows.
- `maintenance/original/`: the four original IT-MAINTENANCE batch/text workflow files, embedded byte-for-byte for the three Maintenance actions.
- `xaml/inputXML.xaml`: WPF UI markup embedded into the compiled script.
- `pester/`: Pester tests for config and function checks.
- `lint/PSScriptAnalyser.ps1`: PowerShell Script Analyzer settings.
- `winutil.ps1`: ignored generated build artifact.

## Goals

- Provide a single-script Windows utility that can be launched from PowerShell.
- Keep development modular enough for contributors to work on functions, config, UI, docs, and tooling independently.
- Make install, tweak, maintenance, repair, and update workflows discoverable from the WPF UI.
- Keep common lists and options declarative in JSON config where possible.
- Preserve a repeatable compile process so local builds and GitHub Actions builds produce the distributable script from the same inputs.

## Non-Goals

- `winutil.ps1` is not hand-maintained.
- The project is not structured as a PowerShell module at runtime.
- The GUI is not a separate packaged desktop application in this repository's normal release path.
- Generated files should not be reviewed as source changes.

## Build Model

`Compile.ps1` combines the repository sources into `winutil.ps1` in this order:

1. Read `scripts/start.ps1` and replace `#{replaceme}` with the current `yy.MM.dd` build date.
2. Append every file under `functions/` recursively.
3. Convert each `config/*.json` file into embedded `$sync.configs` objects.
4. Special-case `config/applications.json` so keys receive the `WPFInstall` prefix in compiled config.
5. Encode each `maintenance/*.ps1` script as UTF-8/base64 and embed the payload dictionary into `$sync.configs.maintenanceScripts`.
   Embed `maintenance/original/*` as raw bytes/base64 in `$sync.configs.maintenanceOriginalFiles`.
6. Embed `xaml/inputXML.xaml` into `$inputXML`.
7. Append `scripts/main.ps1`.
8. Write the result to root `winutil.ps1` as UTF-8, preserving Vietnamese account-name normalization on Windows PowerShell 5.1.

Because the final script is concatenated, code cannot rely on runtime module imports or source-relative dot-sourcing unless the compiled script will also contain the required code/data.

## Runtime Model

- WinUtil runs in PowerShell on Windows and uses WPF for the UI.
- Shared mutable state is stored in `$sync`, including configs, UI element references, runspace state, selections, and progress.
- Long-running operations use runspaces or existing async patterns so the UI remains responsive.
- UI updates from background work are dispatched back to the WPF UI thread.
- Windows Update changes and service-state queries, including initial refresh, run in the background. A UI-runspace completion delegate is queued with Dispatcher.BeginInvoke; it applies the returned state and releases the busy flag before displaying errors. Workers never synchronously dispatch status queries or dialogs.
- Clicking Activation (or Alt+C) launches `irm https://get.activated.win | iex` through a hidden Windows PowerShell bootstrap that opens the external MAS menu, without an inner launch button. Only explicit navigation through `Invoke-WPFButton` launches MAS; tab initialization does not. It does not wait on the WPF thread, choose an activation method, or report activation success. The bootstrap console is hidden, has no custom title or -NoExit flag, and closes when its command finishes; the interactive MAS menu retains its own lifecycle. WinUtil records only process launch status in its session log.
- Declarative features such as apps, tweaks, presets, DNS providers, and navigation stay in `config/*.json` unless code is required.

## UI And Event Contract

- UI layout lives in `xaml/inputXML.xaml`.
- Named WPF controls are discovered and stored in `$sync`.
- Button/action wiring follows a naming convention: an element named like `WPFThingButton` maps to a function named like `Invoke-WPFThingButton`.
- Main navigation contains Application (Alt+I), Update (Alt+U), Activation (Alt+C), Tweaks, Maintenance, and AppX Removal (Alt+A). Maintenance groups its task switches, report button, synchronized Windows Update switch, and Task Scheduler viewer in one compact panel, with all fourteen Legacy Windows Panels shortcuts in a second column. WinGet reinstall lives in a separate Package Management panel below both. Config, optional Features, other Fixes, PowerShell Profile, and Remote Access controls have been removed. AppX has its own navigation button; there is no AppX shortcut in Tweaks. Calculator, Notepad, Paint, Photos, Snipping Tool, Camera, Media Player, Sticky Notes, Clock, and To Do are excluded from the AppX catalog and presets. Tab numbers follow this order, with AppX last. The Settings menu, search bar, and category filter chips are removed; command-line `-Config` imports remain supported through `Import-WinUtilConfig`. Legacy Windows Panels centers its heading and shortcut buttons within its own column.

## Configuration Contract

- Config files must remain valid JSON and compile cleanly through `ConvertFrom-Json`.
- `config/applications.json` defines installable applications; each entry includes the fields expected by tests and UI code, such as package manager IDs, category, display content, description, and link.
- `config/update.json` defines shortcuts to Windows Update Settings (`ms-settings:windowsupdate`) and Store Downloads (`ms-windows-store://downloadsandupdates`), plus a Windows Update state switch synchronized with its Maintenance twin. The Update content is capped at 800 units (double its previous 400) and split into two responsive columns. Opening Update only reads switch state and never applies changes.
- `config/tweaks.json` defines Windows tweaks; registry and service changes include original values or original states when applicable so undo workflows can restore user systems.
- Preset and navigation files reference valid config keys. Renaming a config key requires updating all presets, UI references, docs, and code paths together.
- `config/maintenance.json` defines two columns: a compact ordered IT-MAINTENANCE panel with closely spaced switch labels and controls, and Legacy Windows Panels. The maintenance workflows include switches that create/remove the original daily shutdown and cleanup tasks, create/remove the C:/D:/E: monitoring task, plus a button that exports software/DxDiag reports immediately. Buttons dispatch through their maintenance `Action`, existing `function`, or `InvokeScript` metadata. Retired feature keys are rejected by strict imports and reported as skipped in legacy imports. Switches refresh from actual system state after each operation. Removing a task keeps installed files and reports. The maintained monitor extends the original payload with optional warnings-only E: checks (30 GB warning, below 20 GB critical), without hiding E: or changing the original C:/D: disk optimization and D: hiding/restoration behavior. Reinstall the monitoring task to deploy this extension on existing machines. The UI confirms the original cleanup and D: hiding behavior and uses the shared runspace pool. Original files are deployed under protected `C:\IT-MAINTENANCE` with backups; no account setup or restart is required for report export.

## Safety Requirements

- Registry, service, package manager, Windows Update, and AppX removal operations affect the host system and are treated as high-risk.
- Tweak changes include undo metadata when the schema supports it, so changes stay reversible.
- Windows Update switch completion reports applied configuration, not an unconditional restart requirement. A restart requested by Windows after installing updates is separate.

## Project Documentation

README.md covers usage and SPEC.md records the architecture and build contract. The Astro/Starlight website, documentation generator, and Pages deployment have been removed. WinUtil builds independently from the PowerShell sources.

## Testing And CI

- `.\Compile.ps1` verifies the compiler can generate `winutil.ps1`.
- `.\Compile.ps1 -Run` compiles and launches the generated utility for manual GUI verification.
- Pester 5.8.0 runs the suite under `pester/*.Tests.ps1`. GitHub Actions (`unittests.yaml`) installs Pester 5.8.0 fresh and runs with `-CI`, which produces `testResults.xml` and exits non-zero on failure.
- GitHub Actions also runs PowerShell Script Analyzer with `lint/PSScriptAnalyser.ps1` on every push.
- The generated `winutil.ps1` may appear locally after compile. It remains ignored build output (see root `.gitignore`) and must not be committed.

## Release Artifact

GitHub Actions is responsible for producing the release `winutil.ps1` from repository sources. A release is considered valid only if the generated script came from the compile process, not from direct manual edits to `winutil.ps1`.

For this fork, `Build-Portable.ps1` also prepares local assets for manual upload: `winutil.ps1`, its plain 64-character SHA-256 file `winutil.ps1.sha256`, `TamphanITtools.cmd`, and `TamphanITtools-portable.zip`. The ZIP contains the launcher, script, and checksum. These outputs remain ignored. No release or workflow is changed by packaging.

The launcher downloads the script and checksum from `https://github.com/pttbk9cqt/TamphanITtools/releases/latest/download`, validates the checksum and PowerShell syntax, and requests UAC through Windows PowerShell 5.1 with `-File`. Downloads use a per-invocation GUID temporary directory retained until the elevated process exits, then cleaned up. Failure or cancelled UAC does not start a fallback or change system execution policy. The checksum provides download consistency, not publisher authentication.

Explicit `offline` mode runs the adjacent script with `-Offline`, without fetching anything. Neither launch mode passes presets or automatically starts system changes. When the compiled script must relaunch an in-memory invocation, it uses this fork's stable release URL, not the upstream repository. A stable public release with both required assets is necessary for online mode; a source-only release or prerelease is insufficient.
