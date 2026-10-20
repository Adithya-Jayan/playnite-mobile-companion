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
