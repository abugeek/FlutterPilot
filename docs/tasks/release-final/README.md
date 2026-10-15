# Sprint 7: Release Readiness & Final Verification

Sprint started: 2026-10-15.
Orchestrator: Antigravity | Implementer: DeepSeek 4.1 Flash (OpenCode)

## Core Mission
Merge Sprint 6 into `main`, verify live subscription notifications against the field lab app, validate workspace-wide pub publishing with zero warnings, and prepare release artifacts.

## Tasks and Execution Order

| # | Task | Description | Depends on | Branch |
|---|---|---|---|---|
| 28 | [28-merge-and-verify-subscriptions.md](28-merge-and-verify-subscriptions.md) | Merge PR #138, sync `main`, run workspace unit & analyzer suite | — | ✅ Merged in bffb9e2 |
| 29 | [29-full-publish-check.md](29-full-publish-check.md) | Run `tool/publish_check.dart` across all 15 packages to verify 0 publish warnings | 28 | ✅ Complete (All 15 packages clean) |
| 30 | [30-release-changelog-audit.md](30-release-changelog-audit.md) | Audit package changelogs, verify documentation parity across all packages | 29 | ✅ Merged in e2c5984 |
