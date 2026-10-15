# 20 · CI Desktop Test Parity (Windows Full Test Matrix)

**Branch:** `ci/windows-matrix` from `main` · **Depends on:** 15

## Goal
Expand the GitHub Actions `unit.yml` Windows job (`windows-process-code`) to run the complete `packages/flutterpilot_server` test suite on Windows (now that all 692 tests pass cleanly on Windows thanks to tasks 10 & 14), closing the open item in ROADMAP §11.

## Why this matters
Earlier, Windows was only running 2 isolated test files in CI (`app_launcher_test.dart` and `call_log_test.dart`) because several path and command-line tests used to fail on Windows. Tasks 10 and 14 fixed all Windows path normalization and command execution issues. Now, every single server test passes on Windows. Running the full suite in CI prevents Windows regressions from ever slipping through again.

## Specification

### 1. Update `.github/workflows/unit.yml`
In the `windows-process-code` job:
- Change the step to run the full server test suite:
  ```yaml
  - name: Server tests on Windows
    working-directory: packages/flutterpilot_server
    run: |
      dart pub get
      dart test
  ```
- Keep the CLI test step (`dart test` in `packages/flutterpilot_cli`).
- Optionally add a check for `tool/check_plugin_ranges.dart`.

### 2. Verify Locally
- Run `dart test` in `packages/flutterpilot_server` (all 692+ tests pass on Windows).
- Run `dart test` in `packages/flutterpilot_cli` (all 84 tests pass on Windows).

### 3. Update Documentation
- Update `ROADMAP.md` §11: Mark Windows server CI coverage complete.

## Done When
- [ ] `.github/workflows/unit.yml` runs full server `dart test` on `windows-latest`.
- [ ] Workflow yaml validates cleanly.
- [ ] Documented in `ROADMAP.md`.
