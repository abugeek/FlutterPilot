# 16 · Standard MCP Resources for Real-Time State Inspection

**Branch:** `feat/mcp-resources` from `main` · **Depends on:** 15

## Goal
Implement first-class standard **MCP Resources** (`resources/list`, `resources/read`) so agents and IDE clients (Cursor, Claude Desktop, Antigravity, Zed) can inspect app state, error counts, widget hierarchy, and device lists as live context without invoking tools or paying for tool-call round-trips.

## Why this is critical (MCP Skills Alignment)
According to the `mcp-builder` and `mcp-tool-curator` skills, static or ambient state inspection should not force active tool execution. Currently, an agent must invoke `get_app_summary` or `get_errors` just to check if the app is alive or if an action caused an error. Standard MCP resources provide a clean, standardized, zero-overhead way to attach live app context.

**Crucially:** Resources do **not** add a single byte to `tools/list`, preserving our tight token budgets.

## Specification

### 1. Resources to Register

Register 5 standard resources in `packages/flutterpilot_server/lib/flutterpilot_server.dart`:

| Resource URI | Name | MIME Type | Description / Content |
|---|---|---|---|
| `flutterpilot://app/summary` | App Summary | `application/json` | Current connection state, active device ID, platform, build mode, current route, and error count. |
| `flutterpilot://app/errors` | Active App Errors | `application/json` | List of uncaught exceptions and layout overflows with file locations and freshness markers. |
| `flutterpilot://app/widget-tree` | Widget Tree | `text/plain` | Formatted compact widget hierarchy of the current screen (reusing tree formatter). |
| `flutterpilot://app/logs` | Debug Logs | `text/plain` | Recent console logs (merged pre-connect buffer + active stream). |
| `flutterpilot://devices` | Device Fleet | `application/json` | Connected and registered devices (`default`, platform, URI, active status). |

### 2. Implementation Details

- In `packages/flutterpilot_server/lib/flutterpilot_server.dart`:
  - Add method `void _registerResources()` called during `_initServer()`.
  - Use `server.registerResource(ResourceMetadata(description: '...', mimeType: '...'), callback, uri: uri)`.
  - Ensure server capabilities include resources with `listChanged: true`.
  - When the app connects, disconnects, or registers new devices, emit `server.sendResourceListChanged()`.
  - Resource callbacks return `ReadResourceResult(contents: [TextResourceContents(uri: uri, text: content, mimeType: mimeType)])`.
  - If no app is connected, return appropriate fallback JSON/text (e.g., `{"connected": false, "message": "No Flutter app currently connected"}`).

### 3. Tests

Create `packages/flutterpilot_server/test/mcp_resources_test.dart`:
- `resources/list` returns the 5 registered resources with valid URIs, MIME types, and descriptions.
- `resources/read` for `flutterpilot://app/summary` returns structured JSON.
- `resources/read` for `flutterpilot://app/errors` returns current error list.
- `resources/read` for `flutterpilot://app/widget-tree` returns text tree.
- `resources/read` for `flutterpilot://devices` returns device fleet list.
- `resources/read` on an invalid URI returns a clear error.
- Verify `tool_registration_test.dart` and `tool_list_report_test.dart` remain completely green (0 tool list byte impact).

## Done When
- [ ] 5 standard resources registered and discoverable via `resources/list`.
- [ ] `resources/read` returns correct contents for connected and disconnected states.
- [ ] `mcp_resources_test.dart` passes.
- [ ] All existing server tests, CLI tests, and budget tests pass.
- [ ] Documented in `CLAUDE.md` and `README.md`.
