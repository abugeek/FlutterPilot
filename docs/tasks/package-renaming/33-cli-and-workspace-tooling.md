# 33 · CLI and Workspace Tooling Renaming (`fp_cli`, `publish_check.dart`, `melos.yaml`)

**Branch:** `refactor/rename-cli-tooling` from `main` (or after Task 32) · **Depends on:** 31, 32

## Goal
Rename the CLI package from `flutterpilot_cli` to `fp_cli`, register dual executables (`fp` and `flutterpilot`), update project generators and diagnostics to use `fp_*` dependencies, update workspace orchestration scripts (`melos.yaml` and `tool/publish_check.dart`), and verify workspace-wide pub publishing with zero warnings.

---

## Detailed Steps

### 1. Rename CLI Package Directory
```bash
git checkout -b refactor/rename-cli-tooling
git mv packages/flutterpilot_cli packages/fp_cli
```

### 2. Update `packages/fp_cli`
1. **`pubspec.yaml`**:
   - Change `name: flutterpilot_cli` ➔ `name: fp_cli`
   - Expose dual executables:
     ```yaml
     executables:
       fp: fp
       flutterpilot: fp
     ```
2. **Binary Entrypoints (`bin/`)**:
   - Rename `bin/flutterpilot.dart` ➔ `bin/fp.dart` (or create `bin/fp.dart` and forward from `bin/flutterpilot.dart`).
3. **Internal Imports**:
   - Rename `lib/flutterpilot_cli.dart` ➔ `lib/fp_cli.dart` (keep backward-compat export in `lib/flutterpilot_cli.dart`).
   - Update imports across `lib/src/` and `test/` to `package:fp_cli/...`.
4. **Commands**:
   - `init_command.dart`:
     - Updates dependency injection to `fp_sdk: ^0.1.0` and detected `fp_*` plugins (`fp_dio`, `fp_bloc`, `fp_riverpod`, etc.).
     - Injects `import 'package:fp_sdk/fp_sdk.dart';`.
     - In `.mcp.json` / Claude / Cursor config, uses `fp_server` (and server name `"fp"` / `"flutterpilot"`).
   - `mcp_command.dart`:
     - Updates server package lookup to `packages/fp_server` and `bin/fp_server.dart`.
     - Updates host compile and binary targets (`fp_server` / `fp_server.exe`).
   - `smoke_command.dart`:
     - Updates default executable lookups to `fp_server` / `bin/fp_server.dart`.
   - `doctor_command.dart`:
     - Checks for `fp_sdk` and `fp_*` plugin presence in `pubspec.yaml`.
     - Checks for `fp_server` in MCP client configuration.
5. **CLI Tests**:
   - Update tests in `packages/fp_cli/test/` to reflect new names.
   - Verify all 84 CLI tests pass.

### 3. Update Workspace Tooling & Reference Apps
1. **`melos.yaml`**:
   - Update `server:run` script to `dart run packages/fp_server/bin/fp_server.dart`.
2. **`tool/publish_check.dart`**:
   - Update package paths:
     ```dart
     final packages = [
       'packages/fp_sdk',
       ...plugins,
       'packages/fp_server',
       'packages/fp_cli',
     ];
     ```
   - Update temporary override logic for `fp_sdk`.
3. **Reference App (`examples/flutter_pilot_example`)**:
   - Update `pubspec.yaml` dependencies from `flutterpilot_sdk` / `flutterpilot_*` to `fp_sdk` / `fp_*`.
   - Update Dart imports in `examples/flutter_pilot_example/lib/main.dart`.

---

## Verification Commands

1. **CLI Tests**:
   ```bash
   cd packages/fp_cli
   dart test
   cd ../..
   ```
2. **Workspace Static Analysis**:
   ```bash
   dart analyze
   ```
   Must produce 0 errors.
3. **Full Dry-Run Publish Verification**:
   ```bash
   dart run tool/publish_check.dart
   ```
   All 15 packages must report `✅` with **0 warnings**.

---

## Done When
- [x] `packages/fp_cli` renamed with dual executables `fp` and `flutterpilot`.
- [x] `init_command` generates `fp_sdk` & `fp_*` dependencies and imports.
- [x] `doctor_command` audits `fp_sdk` and `fp_*` plugins.
- [x] All 84 CLI tests pass.
- [x] `melos.yaml`, `tool/publish_check.dart`, and `examples/flutter_pilot_example` updated.
- [x] Workspace `dart analyze` has 0 errors.
- [x] `dart run tool/publish_check.dart` reports all 15 packages ready to publish with 0 warnings.
- [x] Merged into `main` via PR #142.
