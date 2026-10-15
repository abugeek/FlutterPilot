# 32 · MCP Server Renaming (`fp_server`)

**Branch:** `refactor/rename-server` from `main` (or after Task 31) · **Depends on:** 31

## Goal
Rename the MCP server package from `flutterpilot_server` to `fp_server`:
- `packages/flutterpilot_server` ➔ `packages/fp_server` (package name `fp_server`)
- Update executable / bin entrypoint: `bin/fp_server.dart` (retaining `bin/flutterpilot_server.dart` as backward-compat wrapper)
- Update all internal Dart imports from `package:flutterpilot_server/...` to `package:fp_server/...`
- Verify that all 748 server unit/integration tests and headless MCP protocol inspector tests pass.

---

## Detailed Steps

### 1. Rename Directory
```bash
git checkout -b refactor/rename-server
git mv packages/flutterpilot_server packages/fp_server
```

### 2. Update `packages/fp_server`
1. **`pubspec.yaml`**:
   - Change `name: flutterpilot_server` ➔ `name: fp_server`
   - Description: `"MCP server bridge for FlutterPilot — connects AI agents to Flutter app runtime."`
2. **Binary Entrypoint**:
   - Move/create `bin/fp_server.dart`.
   - In `bin/flutterpilot_server.dart`, keep a forwarding wrapper:
     ```dart
     import 'fp_server.dart' as server;

     Future<void> main(List<String> args) => server.main(args);
     ```
3. **Internal Imports**:
   - Update `package:flutterpilot_server/flutterpilot_server.dart` ➔ `package:fp_server/fp_server.dart`
   - Rename `lib/flutterpilot_server.dart` ➔ `lib/fp_server.dart` (keep backward-compat export in `lib/flutterpilot_server.dart`).
   - Replace all `import 'package:flutterpilot_server/` with `import 'package:fp_server/` across `lib/`, `test/`, and `tool/`.
4. **Self-referential Test Paths & Tool Scripts**:
   - `test/tool_registration_test.dart`: update `'lib/flutterpilot_server.dart'` to `'lib/fp_server.dart'`.
   - `test/tool_profiles_test.dart`: update `'packages/flutterpilot_server/README.md'` to `'packages/fp_server/README.md'`.
   - `test/tools_doc_generated_test.dart`: update `'packages/flutterpilot_server/tool/generate_tools_doc.dart'` to `'packages/fp_server/tool/generate_tools_doc.dart'`.
   - In `tool/`: update `generate_tools_doc.dart`, `generate_guidance.dart`, `tool_list_report.dart`, `fp_bridge.dart`, `e2e_test.dart`, and `run_evals.dart` references from `flutterpilot_server` to `fp_server`.
   - In root `melos.yaml`: update `server:run` to `dart run packages/fp_server/bin/fp_server.dart`.

---

## Verification Commands

1. **Static Analysis**:
   ```bash
   cd packages/fp_server
   dart analyze .
   ```
2. **Run Server Test Suite**:
   ```bash
   dart test
   ```
   All 748 tests must pass.
3. **Run Guidance & Doc Tests**:
   ```bash
   dart test test/guidance_generated_test.dart test/guidance_names_test.dart test/tool_profiles_test.dart
   ```
4. **Run Headless MCP Protocol Inspector**:
   ```bash
   dart test test/mcp_protocol_compliance_test.dart
   ```

---

## Done When
- [x] `packages/fp_server` directory renamed.
- [x] `name: fp_server` in `pubspec.yaml`.
- [x] All 748 unit, integration, and MCP protocol tests pass.
- [x] 0 analyzer errors in `packages/fp_server`.
- [x] Merged into `main` via PR #141.
