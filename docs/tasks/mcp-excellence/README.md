# Round 4: MCP Excellence & Agent Superpowers

Sprint started: 2026-10-15.
Orchestrator: Antigravity | Implementer: DeepSeek 4.1 Flash (OpenCode)

## Core Mission

Elevate FlutterPilot from an outstanding MCP server into the gold standard of agentic Flutter tooling:
1. **Zero-Token Inspection**: Implement standard **MCP Resources** (`resources/list`, `resources/read`) so agents and IDE clients can inspect app health, widget trees, errors, and device lists without burning tool-call round-trips.
2. **Intent-Driven Workflows**: Implement curated **MCP Prompts** (`prompts/list`, `prompts/get`) that guide models into high-accuracy diagnostic and testing loops.
3. **Machine-Readable API Twin**: Expand `structuredContent` to all primary diagnostic and action batch tools (`get_errors`, `get_app_summary`, `execute_action_chain`, `fill_form`).
4. **Rigorous Protocol Compliance**: Add an automated headless MCP Inspector testing harness verifying JSON-RPC 2.0 framing, capability exchange, schema validation, and error self-correction.
5. **CI Desktop Matrix**: Add Windows test coverage to GitHub Actions to prevent cross-platform regressions.

## Tasks and Execution Order

| # | Task | Description | Depends on | Branch | Status |
|---|---|---|---|---|---|
| 15 | [15-merge-and-sync.md](15-merge-and-sync.md) | Merge PR #128, pull `main`, verify clean baseline across all 4 packages | — | `main` | ✅ Complete (merged #128) |
| 16 | [16-mcp-resources.md](16-mcp-resources.md) | MCP Resources: `flutterpilot://app/*` and `flutterpilot://devices` | 15 | `feat/mcp-resources` | ✅ Merged (#129) |
| 17 | [17-curated-prompts.md](17-curated-prompts.md) | MCP Prompts: workflow prompts for overflow, errors, tests, audit | 15 | `feat/mcp-prompts` | ✅ Merged (#130) |
| 18 | [18-structured-results-action-tools.md](18-structured-results-action-tools.md) | Structured results for `get_errors`, `get_app_summary`, `execute_action_chain`, `fill_form` | 15 | `feat/structured-diagnostics` | ✅ Merged (#131) |
| 19 | [19-mcp-protocol-inspector.md](19-mcp-protocol-inspector.md) | Headless MCP Inspector compliance test harness | 16, 17 | `feat/protocol-inspector-tests` | ✅ Merged (#132) |
| 20 | [20-desktop-ci-parity.md](20-desktop-ci-parity.md) | Windows CI test runner matrix in GitHub Actions | 15 | `ci/windows-matrix` | ✅ Complete (PR #133 open & verified) |

Sprint 4 is complete! All tasks executed, verified, and integrated.

## Rules for DeepSeek 4.1 Flash

1. **One Branch & One PR per Task**: Branch from up-to-date `main`. Never push directly to `main`.
2. **Zero Byte-Budget Regressions**: Never raise byte budgets in `test/tool_registration_test.dart` or `test/tool_list_report_test.dart`.
3. **Text Content Remains Identical**: When adding `structuredContent` or resources, existing tool text output must not change.
4. **Full Verification Before Saying Done**:
   - `dart format --set-exit-if-changed .` (touched files)
   - `dart analyze` (0 errors)
   - `dart test` in `packages/flutterpilot_server`
   - `dart test` in `packages/flutterpilot_cli`
   - `flutter test` in `packages/flutterpilot_sdk` and `packages/plugins/flutterpilot_dio`
   - `e2e_test.dart -d windows`
