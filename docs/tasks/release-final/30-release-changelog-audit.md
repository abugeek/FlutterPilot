# 30 · Release Changelogs & Documentation Audit

**Branch:** `docs/release-prep` from `main` · **Depends on:** 29

## Goal
Audit and update `CHANGELOG.md` across `flutterpilot_server`, `flutterpilot_sdk`, and `flutterpilot_cli` to document all features added across Sprints 4, 5, and 6 (Standard MCP Resources, Dynamic Resource Templates, Live Resource Subscriptions, Curated Prompts, Structured Diagnostics, Selector Key Matching, and Windows CI parity), ensuring full release documentation readiness.

## Updates Required

### 1. `packages/flutterpilot_server/CHANGELOG.md`
Under `## Unreleased`, append entries:
- **Standard MCP Resources (`resources/list`, `resources/read`)**: `flutterpilot://app/summary`, `flutterpilot://app/errors`, `flutterpilot://app/widget-tree`, `flutterpilot://app/logs`, and `flutterpilot://devices` allow AI clients to read live app context with 0 token overhead on tool lists and without executing tool calls.
- **Dynamic MCP Resource Templates (RFC 6570)**: `flutterpilot://app/widgets/{key}` (`widget_by_key`) fetches single-widget properties and subtrees; `flutterpilot://app/routes/{path}` (`route_by_path`) queries navigation state and router parameters.
- **Live MCP Resource Subscriptions**: `resources/subscribe`, `resources/unsubscribe`, and asynchronous `notifications/resources/updated` push notifications when routes change, unhandled exceptions/overflows occur, apps connect/disconnect, or hot reloads run.
- **Curated Workflow Prompts (`prompts/list`, `prompts/get`)**: `debug_layout_overflow`, `diagnose_exception`, `create_integration_test`, and `audit_screen_health` guide agent execution loops deterministically.
- **Machine-Readable Diagnostics (`structuredContent`)**: Added typed JSON twin payloads to `get_app_summary`, `get_errors`, `execute_action_chain`, and `fill_form` (with `failedFields` tracking).
- **Headless MCP Protocol Inspector Test Suite**: 5-matrix stdio compliance suite verifying handshake, schema discovery, JSON-RPC errors, argument validation, and resource subscriptions.
- **Windows Platform Parity**: `tool/publish_check.dart` executes via shell on Windows; GitHub Actions runs the full 748-test server suite on `windows-latest`.

### 2. `packages/flutterpilot_sdk/CHANGELOG.md`
Under `## Unreleased`, append entries:
- **`Type['key']` Selector Matching**: `_findSingleElementUnder` resolves `Type['key']` selectors (e.g. `TextField['checkout_name']`, `Checkbox['accept_terms']`) against the widget's key or semantics ID in addition to visible label text; `_isMatchingType` maps controls to their `*ListTile` wrappers (`CheckboxListTile`, `SwitchListTile`, `RadioListTile`).
- **Form Inspection**: `ext.flutterpilot.fillForm` tracks and reports unresolved field selectors in structured `failedFields`.

### 3. Verification
1. Run guidance generation tests to ensure doc consistency:
   ```bash
   cd packages/flutterpilot_server
   dart test test/guidance_generated_test.dart test/guidance_names_test.dart test/tool_profiles_test.dart
   ```
2. Run analyzer across repository:
   ```bash
   cd ../..
   dart analyze
   ```
   Confirm 0 errors.

## Done When
- [x] `packages/flutterpilot_server/CHANGELOG.md` updated.
- [x] `packages/flutterpilot_sdk/CHANGELOG.md` updated.
- [x] Tests and analyzer clean (18 guidance tests passed, 0 analyze errors).
- [x] PR #139 opened and verified.
