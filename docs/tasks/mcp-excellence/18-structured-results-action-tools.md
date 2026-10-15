# 18 · Machine-Readable Structured Results for Action & Diagnostic Tools

**Branch:** `feat/structured-diagnostics` from `main` · **Depends on:** 15

## Goal
Extend `CallToolResult.structuredContent` (first introduced in task 06 for verdict tools) to primary diagnostic and batching tools: `get_errors`, `get_app_summary`, `execute_action_chain`, and `fill_form`.

## Why this is critical
Automated agent loops, CI scripts, and fleet orchestrators parse text to find out if an error exists or if an action chain failed at step 2. Adding `structuredContent` provides a direct, typed JSON twin alongside the human-readable text.

The text output remains **100% byte-identical** so models reading text and existing tests notice zero changes.

## Specification

### 1. Tools and Structured Content Shapes

| Tool | Structured JSON Shape | Description |
|---|---|---|
| `get_errors` | `{"hasErrors": bool, "count": int, "errors": [{"kind": "exception"\|"overflow", "message": string, "location": string?, "beforeReload": bool}]}` | Summary of errors on screen; empty list when clean. |
| `get_app_summary` | `{"connected": bool, "device": string?, "platform": string?, "route": string?, "errorCount": int, "buildMode": string?}` | Key runtime facts about the connected app. |
| `execute_action_chain` | `{"passed": bool, "completedSteps": int, "totalSteps": int, "failedStep": int?, "failureReason": string?}` | Step execution breakdown of the chain. |
| `fill_form` | `{"submitted": bool, "filledCount": int, "totalFields": int, "failedField": string?}` | Form filling summary and failure point if any. |

### 2. Implementation Rules

1. **Text Content Must Not Change**: Build `structuredContent` from the same underlying variables/objects that format the text response. Do not parse the formatted text backwards.
2. **Result Wrappers Must Preserve `structuredContent`**: Ensure `_registerTool` wrappers (batch nudge tip, image downscale, hang diagnosis, native crash) pass `structuredContent` through when reconstructing `CallToolResult`.
3. **No Output Schema on `tools/list`**: As determined in task 06, declaring schemas on `tools/list` inflates list bytes and token costs. Return `structuredContent` directly on `CallToolResult` without modifying tool registration schemas.
4. **Document Shapes**: Extend the structured results section in `TOOLS.generated.md` (via `generate_tools_doc.dart`) so consumers know the exact JSON shapes.

### 3. Tests

In `packages/flutterpilot_server/test/structured_results_test.dart`:
- Add test groups for `get_errors`, `get_app_summary`, `execute_action_chain`, and `fill_form`.
- Verify `structuredContent` is present and matches the schema for:
  - Success cases
  - Partial failure cases (e.g., chain fails at step 2 of 5)
  - Not connected / error states
- Verify text snapshots remain byte-identical.
- Verify `tool_registration_test.dart` and `tool_list_report_test.dart` continue to pass.

## Done When
- [ ] Four tools return typed `structuredContent` on every path.
- [ ] Text output is completely unmodified.
- [ ] `structured_results_test.dart` passes.
- [ ] `TOOLS.generated.md` updated with the new structured shapes.
- [ ] All package test suites pass.
