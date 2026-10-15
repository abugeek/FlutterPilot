# 19 · Headless MCP Inspector & Protocol Compliance Test Suite

**Branch:** `feat/protocol-inspector-tests` from `main` · **Depends on:** 16, 17

## Goal
Build an automated, headless protocol compliance test suite based on the `mcp-inspector-tester` skill. This suite verifies JSON-RPC 2.0 framing, capability exchange, schema discovery across all endpoints, and argument serialization robustness over real stdio process communication.

## Why this is critical (MCP Skills Alignment)
The `mcp-inspector-tester` skill emphasizes that manual inspector testing is necessary but automated regression testing against protocol standards is what guarantees zero-crash production behavior. Different AI clients serialize arguments differently (some pass numbers as strings, some stringify JSON arrays, some omit optional fields). An automated protocol harness ensures complete client interoperability before release.

## Specification

### 1. Test Harness: `test/mcp_protocol_compliance_test.dart`

Implement an automated test suite in `packages/flutterpilot_server/test/mcp_protocol_compliance_test.dart` that runs FlutterPilot as a subprocess over stdio and executes the full MCP test matrix:

#### Matrix 1: Handshake & Capability Negotiation
- Client sends `initialize` with standard capabilities (`roots`, `sampling`, `experimental`).
- Server returns protocol version, server info (`FlutterPilot`, version), and declared capabilities:
  - `tools`: `listChanged: true`
  - `resources`: `listChanged: true`, `subscribe: true`
  - `prompts`: `listChanged: false`
  - `logging`: `{}`
- Client sends `notifications/initialized`.

#### Matrix 2: Schema Discovery Audit
- `tools/list`:
  - Every tool has non-empty snake_case `name` and descriptive `description`.
  - `inputSchema` is a valid JSON schema with `type: "object"`.
  - Every tool has valid `annotations` (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`).
- `resources/list`:
  - Returns registered `flutterpilot://` URIs with valid `mimeType` and description.
- `prompts/list`:
  - Returns all registered prompts (`flutterpilot_guide` + workflow prompts).

#### Matrix 3: Standard JSON-RPC Error Handling
- Unknown method -> returns standard `-32601 Method not found`.
- Malformed JSON string on stdin -> returns standard `-32700 Parse error`.
- Invalid request structure -> returns standard `-32600 Invalid Request`.

#### Matrix 4: Tool Invocation & Serialization Robustness
- Call tool with stringified arguments (e.g. string numbers, string booleans) -> verify clean execution or graceful coercion.
- Call tool with unknown extra arguments -> verify clean refusal naming the extra argument.
- Call tool with missing required argument -> verify clean refusal naming the missing argument.
- Ensure no type error ever returns the old "app was busy, retry" message.

### 2. Integration
- The test runs as a standard unit test: `dart test test/mcp_protocol_compliance_test.dart`.
- Runs cleanly without requiring an active Flutter app (tests offline/disconnected behavior and protocol layer).

## Done When
- [ ] `mcp_protocol_compliance_test.dart` created and passing.
- [ ] Full handshake, discovery, error handling, and serialization matrices covered.
- [ ] Server handles all protocol edge cases with standard JSON-RPC codes.
- [ ] All tests in `flutterpilot_server` pass.
