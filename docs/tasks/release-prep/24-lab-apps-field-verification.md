# 24 · Lab App Field Verification (fp_lab_shop)

**Branch:** `docs/field-test-sprint5` from `main` · **Depends on:** 21

## Goal
Drive `../fp_lab_shop` through `tool/fp_bridge.dart` to verify the newly added MCP features against a real running Flutter application:
1. Standard MCP Resources (`flutterpilot://app/summary`, `flutterpilot://app/errors`, `flutterpilot://app/widget-tree`, `flutterpilot://app/logs`, `flutterpilot://devices`).
2. Curated MCP Prompts (`debug_layout_overflow`, `diagnose_exception`, `create_integration_test`, `audit_screen_health`).
3. Machine-readable `structuredContent` twin on `get_errors`, `get_app_summary`, `execute_action_chain`, `fill_form`.

## Steps
1. In `../fp_lab_shop`, launch the app:
   ```bash
   flutter run -d windows
   ```
2. Start the bridge from FlutterPilot repo root:
   ```bash
   dart run packages/flutterpilot_server/tool/fp_bridge.dart -p ../fp_lab_shop --allow-destructive
   ```
3. Test tool calls and verify structured responses via curl:
   ```bash
   curl -s localhost:8765 -d '{"name":"get_app_summary","arguments":{}}'
   curl -s localhost:8765 -d '{"name":"get_errors","arguments":{}}'
   ```
4. Record observations and add any findings to `docs/field-test-findings.md`.
