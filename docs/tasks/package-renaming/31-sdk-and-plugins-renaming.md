# 31 · SDK and Plugins Renaming (`fp_sdk` & 12 `fp_*` Plugins)

**Branch:** `refactor/rename-sdk-plugins` from `main` · **Depends on:** none

## Goal
Shorten package names for the core SDK and all 12 official plugins:
- `packages/flutterpilot_sdk` ➔ `packages/fp_sdk` (package name `fp_sdk`)
- `packages/plugins/flutterpilot_*` ➔ `packages/plugins/fp_*` (package names `fp_*`)

Provide seamless migration by retaining deprecated forwarding exports in `lib/flutterpilot_*.dart`, updating all internal tests, and verifying that static analysis and unit tests pass.

---

## Detailed Steps

### 1. Rename Directories
Use `git mv` to preserve git history:
```bash
git checkout -b refactor/rename-sdk-plugins

# SDK
git mv packages/flutterpilot_sdk packages/fp_sdk

# Plugins
git mv packages/plugins/flutterpilot_bloc packages/plugins/fp_bloc
git mv packages/plugins/flutterpilot_connectivity packages/plugins/fp_connectivity
git mv packages/plugins/flutterpilot_dio packages/plugins/fp_dio
git mv packages/plugins/flutterpilot_drift packages/plugins/fp_drift
git mv packages/plugins/flutterpilot_firebase packages/plugins/fp_firebase
git mv packages/plugins/flutterpilot_gorouter packages/plugins/fp_gorouter
git mv packages/plugins/flutterpilot_hive packages/plugins/fp_hive
git mv packages/plugins/flutterpilot_riverpod packages/plugins/fp_riverpod
git mv packages/plugins/flutterpilot_secure_storage packages/plugins/fp_secure_storage
git mv packages/plugins/flutterpilot_shared_preferences packages/plugins/fp_shared_preferences
git mv packages/plugins/flutterpilot_sqflite packages/plugins/fp_sqflite
git mv packages/plugins/flutterpilot_supabase packages/plugins/fp_supabase
```

### 2. Update `packages/fp_sdk`
1. **`pubspec.yaml`**:
   - Change `name: flutterpilot_sdk` ➔ `name: fp_sdk`
   - Description: `"Core FlutterPilot SDK for AI-native runtime introspection of Flutter applications."`
2. **Library entrypoint**:
   - Rename/move `lib/flutterpilot_sdk.dart` ➔ `lib/fp_sdk.dart`.
   - Add a backward-compatibility forwarder in `lib/flutterpilot_sdk.dart`:
     ```dart
     @Deprecated('Import package:fp_sdk/fp_sdk.dart instead.')
     library;

     export 'fp_sdk.dart';
     ```
3. **Tests (`packages/fp_sdk/test/`)**:
   - Update imports from `package:flutterpilot_sdk/flutterpilot_sdk.dart` to `package:fp_sdk/fp_sdk.dart`.
   - Ensure all 253 SDK tests pass.

### 3. Update all 12 Plugins in `packages/plugins/fp_*`
For each plugin `fp_<name>` (`bloc`, `connectivity`, `dio`, `drift`, `firebase`, `gorouter`, `hive`, `riverpod`, `secure_storage`, `shared_preferences`, `sqflite`, `supabase`):
1. **`pubspec.yaml`**:
   - Change `name: flutterpilot_<name>` ➔ `name: fp_<name>`
   - Change dependency `flutterpilot_sdk` ➔ `fp_sdk: ^0.1.0`
2. **Library entrypoint**:
   - Rename/move `lib/flutterpilot_<name>.dart` ➔ `lib/fp_<name>.dart`.
   - Add a backward-compatibility forwarder in `lib/flutterpilot_<name>.dart`:
     ```dart
     @Deprecated('Import package:fp_<name>/fp_<name>.dart instead.')
     library;

     export 'fp_<name>.dart';
     ```
3. **Tests**:
   - Update tests in `test/` to import `package:fp_<name>/fp_<name>.dart` and `package:fp_sdk/fp_sdk.dart`.

---

## Verification Commands

1. **Bootstrap and Analyze**:
   ```bash
   dart pub get
   dart run melos bootstrap
   dart analyze packages/fp_sdk packages/plugins
   ```
2. **Run SDK and Plugin Tests**:
   ```bash
   cd packages/fp_sdk
   flutter test
   cd ../..
   dart test packages/plugins
   ```
   All SDK and plugin tests must pass with 0 failures and 0 analyzer errors.

---

## Done When
- [x] `packages/fp_sdk` renamed with `name: fp_sdk` and `lib/fp_sdk.dart`.
- [x] All 12 plugin directories renamed to `packages/plugins/fp_*` with `name: fp_*`.
- [x] Backward compatibility forwarders in place (`lib/flutterpilot_*.dart`).
- [x] All 253 SDK tests and all plugin tests pass.
- [x] `dart analyze packages/fp_sdk packages/plugins` reports 0 issues.
- [x] Merged into `main` via PR #140.
