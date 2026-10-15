# Sprint 8: Package Rebranding & Ergonomics (`fp_*`)

Sprint started: 2026-10-15.
Orchestrator: Antigravity | Implementer: DeepSeek 4.1 Flash (OpenCode)

## Core Mission
Shorten all package names across the monorepo from `flutterpilot_*` to `fp_*` (`fp_sdk`, `fp_server`, `fp_cli`, and all 12 `fp_*` plugins) for superior ergonomics, cleaner imports, and dual-binary CLI invocation (`fp` and `flutterpilot`), while maintaining zero warnings on `tool/publish_check.dart` and 100% test passing across the monorepo.

## Tasks and Execution Order

| # | Task | Description | Depends on | Target Branch | Status |
|---|---|---|---|---|---|
| 31 | [31-sdk-and-plugins-renaming.md](31-sdk-and-plugins-renaming.md) | Rename SDK (`packages/fp_sdk`) & 12 plugins (`packages/plugins/fp_*`) | — | `refactor/rename-sdk-plugins` | ✅ Merged (#140) |
| 32 | [32-server-renaming.md](32-server-renaming.md) | Rename MCP Server (`packages/fp_server`) & internal server imports | 31 | `refactor/rename-server` | ✅ Merged (#141) |
| 33 | [33-cli-and-workspace-tooling.md](33-cli-and-workspace-tooling.md) | Rename CLI (`packages/fp_cli`, dual `fp`/`flutterpilot` binary), update `publish_check.dart` & `melos.yaml` | 32 | `refactor/rename-cli-tooling` | ✅ Merged (#142) |
