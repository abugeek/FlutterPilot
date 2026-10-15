# 29 · Full Workspace Pub.dev Publish Validation

**Branch:** `verify/publish-dryrun` from `main` · **Depends on:** 28

## Goal
Run `tool/publish_check.dart` across all 15 packages in the workspace (server, CLI, SDK, and all 12 plugins) to verify that the entire repository passes `pub publish --dry-run` with **0 warnings** and 0 errors.

## Steps
1. Run publish check from the repository root:
   ```bash
   dart run tool/publish_check.dart
   ```
## Done When
- [x] All 15 packages validate with `✅`.
- [x] `All 15 packages are ready to publish.`
- [x] 0 publish warnings across entire workspace.
