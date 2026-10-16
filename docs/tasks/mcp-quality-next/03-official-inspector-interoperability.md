# 03 — Official MCP Inspector interoperability
## Status, priority, and dependencies
Proposed; P1; after tasks 00–02. Estimated 2–3 days. Branch suggestion: `test/official-mcp-inspector`.
## Problem and expected benefit
The raw stdio suite is valuable, but an independently maintained client can reveal compatibility assumptions shared by server-specific tests. Keep both: official Inspector smoke tests for interoperability, raw JSON-RPC tests for malformed framing and persistent-session notifications.
## Verified starting points
- `packages/fp_server/test/mcp_protocol_compliance_test.dart` defines its own `_Inspector`.
- That client discards invalid JSON stdout lines; its comment that the server never writes non-JSON is not an assertion.
- The suite requests `2025-11-25`; the evaluation session currently requests `2024-11-05`.
- `.github/workflows/unit.yml` has no official Node Inspector setup.
- `FlutterPilotServer.start()` uses `StdioServerTransport`. The HTTP bridge under `tool/` is not a production Streamable HTTP MCP transport.
## Scope and non-goals
Add a pinned official CLI check on Windows/Linux, strengthen raw stdio hygiene, and record negotiated versions. Do not replace existing protocol tests, add HTTP transport, or use a browser UI in CI.
## Step-by-step implementation
1. At execution time, resolve a released Inspector version, inspect its package/Node requirements and CLI reference, then pin the exact version with a lockfile in an isolated development-tool directory.
2. Record the upstream source revision and supported protocol era. Do not copy current `main` commands into a different pinned release without testing.
3. Add a portable launcher using argument arrays and explicit working directories. Prefer an explicit temporary read-only Inspector config so CLI/server flag collisions and Windows quoting are deterministic.
4. Start the Dart server with stderr logging and call logging disabled. Use a temporary project without an app for headless tests; explicitly isolate discovery.
5. Probe initialize/capabilities and record actual negotiation. Select a compatible classic-initialize protocol if the pinned client defaults to a newer stateless profile.
6. Check `tools/list`, `resources/list`, `resources/templates/list`, and `prompts/list`; validate representative entries and all-tool discovery separately from normal dynamic listing.
7. Exercise a safe no-app tool, disconnected resource read, and prompt fetch. Assert payloads, not just exit zero.
8. Send typed numbers/booleans, stringified wrong types, missing required values, unknown options, and malformed nested steps through the pinned CLI's native-JSON argument facility. Do not let key/value auto-coercion hide the tested shape.
9. Decode exit classes and `isError` according to the pinned release. Current v2 documentation describes tool errors as exit 5; verify that for the selected version.
10. Make the raw test client fail on nonempty non-JSON stdout or structurally invalid protocol output. Capture bounded, redacted stderr separately; test the detector with an intentionally noisy fake server.
11. Retain raw tests for malformed JSON, IDs, unknown methods, recovery, subscriptions/unsubscribe, and list changes. One-shot CLI invocations do not prove same-session notifications.
12. Add bounded connect/request/shutdown deadlines and process-tree cleanup, including Windows `.bat` descendants. Test cleanup against a deliberately hanging subprocess.
13. Integrate the same wrapper into Linux/Windows jobs; upload sanitized failure reports. Keep Node out of the production Dart runtime.
14. Document a connected-fixture run for dynamic SDK/plugin/core/zero-code behavior. Headless list-all results must not be represented as proving live gating.
## Proposed file boundaries
- Add `packages/fp_server/tool/inspector/` with exact package lock, wrapper, fixture config, and usage notes.
- Modify `.github/workflows/unit.yml` and `packages/fp_server/test/mcp_protocol_compliance_test.dart`.
- Add wrapper parsing/timeout tests and fake stdio fixtures.
- Do not rename the production server or change its transport.
## Validation sequence
1. Test wrapper output, failures, timeout, invalid stdout, and cleanup without network.
2. Run the pinned package against the real server on Windows/Linux.
3. Run the strengthened raw protocol suite.
4. Run a connected disposable fixture and compare normal/core/static visibility.
5. Confirm Node is not required for production `fp_server` installation.
## Acceptance criteria
- Official discovery/call checks pass on both OSes with the same exact release.
- Expected malformed calls fail actionably and leave the server usable.
- Non-JSON stdout fails the raw gate.
- Failed probes cannot leave unbounded subprocesses.
- Reports identify Inspector, Node, Dart, server revision, and requested/negotiated protocols.
- Notifications remain tested over a persistent connection.
## Risks and rollback
Upstream CLI changes and protocol-era differences require exact pins and explicit negotiation. npm outages are setup failures, never server passes. Cache normal dependencies without floating resolution.
Rollback the external job independently; retain improved raw-client assertions.
## Handoff
Leave the wrapper invocation, pinned-tool identity, protocol evidence, and known SDK/client limits for task 04.
