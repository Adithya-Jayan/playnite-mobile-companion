# Agent Instructions

## Project Verification Commands

- **C# Plugin Tests**:
  ```powershell
  dotnet test playnite-exporter-plugin.Tests\PlayniteExporterPlugin.Tests.csproj
  ```
- **Flutter Tests & Linting**:
  ```powershell
  cd playnite-mobile-companion; flutter analyze; flutter test
  ```
- **Unified Full-Suite Runner**:
  ```powershell
  powershell -File scripts/test_all.ps1
  ```

## Packaging and Distribution

- **Unified Packaging Script**:
  ```powershell
  powershell -File scripts/package_dist.ps1 [-SkipApk] [-SkipPext]
  ```
  *(Packages `.pext` directly with all dependency assemblies without stripping, attempts hot-update of installed extension, builds release Flutter APK, and outputs to `dist/`).*
- **Versioning Rule**:
  Always bump version numbers across `playnite-exporter-plugin/extension.yaml`, `playnite-mobile-companion/pubspec.yaml`, and `installer.yaml` whenever packaging distribution artifacts.
- **Playnite Runtime Logs & Paths**:
  - Extensions log: `%APPDATA%\Playnite\extensions.log`
  - Playnite main log: `%APPDATA%\Playnite\playnite.log`
  - Installed extension folder: `%APPDATA%\Playnite\Extensions\MobileDeltaSyncExporter_d3b07384-d113-4c90-951b-10f88a91a92a`

## Subagent Execution Directives

- **Dynamic Subagents**: Always use `TypeName: "self"` unless pre-registered via `define_subagent`.
- **Windows Long Paths**: When using `Workspace: "share"`, keep branch names concise to prevent `Filename too long` errors during worktree pruning.
- **File Searches**: In PowerShell file searches, always pass `-Exclude "build",".dart_tool","bin","obj"` to avoid traversing generated build directories.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues using the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical triage roles (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout (`GLOSSARY.md` and `docs/adr/` at repo root). See `docs/agents/domain.md`.
