# 22 · Windows Support for `tool/publish_check.dart` & Full Pub Dry-Run

**Branch:** `fix/publish-check-windows` from `main` · **Depends on:** 21

## Goal
Make `tool/publish_check.dart` work seamlessly on Windows by adding `runInShell: true` to its `Process.run` invocation, and verify that all 15 packages in the repo pass `pub publish --dry-run` with 0 warnings.

## Problem
On Windows, `flutter` is a batch script (`flutter.bat`). Calling `Process.run('flutter', ...)` without `runInShell: true` throws `ProcessException: The system cannot find the file specified`.

## Fix
In `tool/publish_check.dart`:
1. Add `runInShell: true` to the `Process.run(flutter ? 'flutter' : 'dart', ...)` call.
2. Run from repository root:
   `dart run tool/publish_check.dart`
3. Verify all 15 packages (server, CLI, SDK, and 12 plugins) report clean publish validation.

## Done When
- [x] `dart run tool/publish_check.dart` completes on Windows without throwing.
- [x] All 15 packages validate with 0 warnings.
- [x] PR opened and verified (PR #134).
