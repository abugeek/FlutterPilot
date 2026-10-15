# 23 · Real-Device End-to-End Verification on Windows

**Branch:** `verify/e2e-windows` from `main` · **Depends on:** 21

## Goal
Execute the real-device end-to-end integration test (`tool/e2e_test.dart -d windows` and `--zero-code -d windows`) to ensure all action tools, inspection tools, relaunch behaviors, and cleanups pass on a live Flutter window.

## Steps
1. Run standard SDK mode E2E:
   ```bash
   cd packages/flutterpilot_server
   dart run tool/e2e_test.dart -d windows
   ```
   Verify: `E2E passed` (exit code 0, 160+ checks passed).
2. Run zero-code mode E2E:
   ```bash
   dart run tool/e2e_test.dart --zero-code -d windows
   ```
   Verify: `E2E passed` (exit code 0, 16+ checks passed).
3. Report pass line and execution timing.
