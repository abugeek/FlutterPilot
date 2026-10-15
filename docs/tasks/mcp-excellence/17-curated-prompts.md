# 17 · Curated MCP Workflow Prompts

**Branch:** `feat/mcp-prompts` from `main` · **Depends on:** 15

## Goal
Provide first-class **MCP Prompts** (`prompts/list`, `prompts/get`) for the four most common agent tasks: fixing layout overflows, diagnosing unhandled exceptions, recording integration tests, and auditing screen health.

## Why this matters (MCP Skills Alignment)
The `mcp-builder` and `mcp-tool-curator` skills emphasize that models (especially fast inference models like DeepSeek 4.1 Flash, Haiku, or GPT-4o-mini) perform dramatically better when given structured, intent-level workflow prompts rather than guessing tool sequences. MCP Prompts provide standardized, ready-to-run system/user prompt templates directly through the MCP protocol.

## Specification

### 1. Prompts to Add

In `packages/flutterpilot_server/lib/flutterpilot_server.dart` (inside `_registerPrompts()`):

| Prompt Name | Title | Description | Workflow Steps in Prompt Body |
|---|---|---|---|
| `debug_layout_overflow` | Debug Layout Overflow | Locate, analyze, and fix a RenderFlex layout overflow on screen. | 1. Call `get_errors` to identify the overflow warning and culprit widget.<br>2. Call `inspect_widget(key: "...", layout: true)` to see constraints and overflowing dimensions.<br>3. Open the Dart source file indicated in the error.<br>4. Fix the flex constraint (e.g. wrap in `Expanded`, `Flexible`, or `SingleChildScrollView`).<br>5. Call `hot_reload` and call `get_errors` to verify the overflow is gone. |
| `diagnose_exception` | Diagnose Runtime Exception | Step-by-step diagnostic loop for unhandled exceptions and red screens. | 1. Call `get_errors(report: true)` to get the compact crash report with the failing app frame.<br>2. Call `get_debug_logs(sinceSeconds: 30)` to inspect surrounding logs.<br>3. Inspect the code at the top app frame.<br>4. Fix the issue in source code.<br>5. Call `hot_reload` (or `hot_restart` if state is corrupted) and verify. |
| `create_integration_test` | Create Integration Test | Record actions on the active screen and generate a runnable integration test. | 1. Call `generate_test(start: true)` to restart the app and begin recording.<br>2. Drive the target flow using `tap_widget`, `enter_text`, `wait_for`, and `assert_widget`.<br>3. Call `generate_test(name: "feature_flow")` to generate and run the test on device.<br>4. Verify the test passes and inspect the generated test file. |
| `audit_screen_health` | Audit Screen Health | Audit accessibility, contrast, and layout health on the current screen. | 1. Call `audit_screen_health()`.<br>2. Review unlabeled tappable controls and missing semantic labels.<br>3. Review WCAG contrast issues.<br>4. Review screen reader traversal order.<br>5. Apply fixes in Dart code and `hot_reload`. |

Keep the existing `flutterpilot_guide` prompt unchanged.

### 2. Implementation & Guidance

- Store prompt text cleanly in markdown or constants (e.g. in `packages/flutterpilot_server/guidance/prompts/` or directly in `src/prompts.dart`).
- Register each prompt with `server.registerPrompt(...)`.
- `prompts/get` returns `GetPromptResult(messages: [PromptMessage(role: PromptMessageRole.user, content: TextContent(text: ...))])`.
- If a prompt takes arguments (e.g. optional `screenName` or `errorIndex`), declare `PromptArgument`s.

### 3. Tests

Create `packages/flutterpilot_server/test/mcp_prompts_test.dart`:
- `prompts/list` lists all 5 prompts with titles and descriptions.
- `prompts/get` for each prompt returns valid messages with actionable workflow steps.
- `prompts/get` with an unknown prompt name returns an appropriate error.
- All existing tests pass.

## Done When
- [ ] 4 workflow prompts registered alongside `flutterpilot_guide`.
- [ ] `prompts/list` and `prompts/get` tested in `mcp_prompts_test.dart`.
- [ ] Zero impact on `tools/list` byte budget.
- [ ] Documented in `CLAUDE.md`.
