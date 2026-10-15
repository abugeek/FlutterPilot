# Sprint 5: Production Polish & Release Verification

Sprint started: 2026-10-15.
Orchestrator: Antigravity | Implementer: DeepSeek 4.1 Flash (OpenCode)

## Core Mission
Verify real-device operation, ensure zero-warning pub.dev publish readiness across all 15 packages, and validate the full MCP surface (resources, prompts, structured results) against the live lab apps.

## Tasks and Execution Order

| # | Task | Description | Depends on | Branch |
|---|---|---|---|---|
| 21 | [21-merge-and-sync-ci.md](21-merge-and-sync-ci.md) | Merge PR #133, sync `main`, ensure all 737+ tests pass | — | `main` |
| 22 | [22-publish-check-windows.md](22-publish-check-windows.md) | Fix Windows `Process.run` in `publish_check.dart` (`runInShell: true`); verify all 15 packages dry-run publish clean | 21 | `fix/publish-check-windows` |
| 23 | [23-e2e-real-device-windows.md](23-e2e-real-device-windows.md) | Run real-device e2e tests (`e2e_test.dart -d windows` and `--zero-code -d windows`) | 21 | `verify/e2e-windows` |
| 24 | [24-lab-apps-field-verification.md](24-lab-apps-field-verification.md) | Live lab app check (`../fp_lab_shop`) via `fp_bridge.dart`: test resources, prompts, and structured results | 21 | `docs/field-test-sprint5` |
