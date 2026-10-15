# 06 · Structured results for the pass/fail tools

**Branch:** `feat/structured-results` · **Depends on:** 02

## Goal

Tools whose answer is a verdict return it also as `structuredContent` (MCP
2025-06-18+), so programs (CI, `flutterpilot smoke`, `run_on_devices`'s own
comparison, the eval runner) read `{"passed": false, ...}` instead of
parsing prose. The text content stays exactly as it is: models read the
text; this adds a machine-readable twin.

This is the `mcp-builder` skill's "Output Schema / structuredContent" advice,
applied only where a verdict exists. Not for inspection tools (widget trees,
logs): their value is the prose, and a schema would only cost list bytes.

## Scope: four tools

| Tool | Structured shape (draft; refine from the real results) |
|---|---|
| `assert_widget` | `{passed: bool, found: int, expected?: string, reason?: string}` |
| `wait_for` | `{met: bool, waitedMs: int, route?: string, timedOut: bool}` |
| `verify_feature` (`finish: true` only) | `{feature: string, criteria: [{index: int, text: string, verdict: "passed"\|"failed"\|"not_verified", warnings: int}], report: string}` (`report` = path of report.md) |
| `run_on_devices` | `{devices: [{id: string, passedSteps: int, totalSteps: int, failedStep?: int, route?: string, errors: int}], same: bool}` |

Before designing, read each tool's current result text and the code that
builds it; the structured fields must come from the same values, not from
parsing the text back.

Also check whether `execute_action_chain` and `fill_form` would benefit
(steps passed / failed step). Add them only if a consumer exists (see
"Consumers"); otherwise list them in the PR as candidates.

## Design

### A. mcp_dart support (verify first)

mcp_dart 2.4.2 supports `outputSchema` on `registerTool` and
`structuredContent` on `CallToolResult`, and **validates** the structured
content against the output schema: a tool that declares a schema and returns
non-matching or missing structured content becomes an error
(`mcp_server.dart` ~line 175). Read that code before you start. Consequences:

- Every return path of these tools (success, failure, not connected,
  refused, the catch-all in `_registerTool()`, `_withHangDiagnosis` etc. that
  rebuild `CallToolResult`) must either carry valid structured content or the
  schema must allow it to be absent on errors. Check how mcp_dart treats
  `isError: true` results without structured content.
- The wrappers in `_registerTool()` that rebuild results (batch nudge tip,
  image downscale, phone state, native crash, hang diagnosis) must **copy
  `structuredContent` through**. Today they construct new `CallToolResult`s
  with only `content`/`isError`. This is the most likely bug; test each
  wrapper.

### B. To declare `outputSchema` or not

An `outputSchema` adds bytes to `tools/list` for every session. The spec
allows `structuredContent` without an `outputSchema`. Measure both:

1. Structured content, no output schema: zero list cost.
2. With output schemas: measure the added bytes with task 03's
   `listBytes`.

Default to option 1 unless the added bytes are under ~600 total for the four
tools; report the measurement and your choice. If you choose 1, document the
shapes in `TOOLS.generated.md` (extend `generate_tools_doc.dart` to print a
"Structured result" block from a Dart-side map of shapes) so consumers know
them.

### C. Text stays the same

Existing text content must be byte-identical for the same inputs. Agents and
the e2e test read it. Add snapshot tests for each tool's text before you
change anything (run them on base first), then keep them green.

For backwards compatibility the spec suggests also putting the JSON in a text
block. **Don't**: it would double the response tokens for every model. Clients
that don't understand `structuredContent` still get the prose.

### D. Consumers (make at least one real)

A structured result nobody reads is dead weight. In this PR switch at least
one in-repo consumer from text parsing to structured content:

- `run_on_devices` / `fleet_compare.dart`: does it parse step results from
  text? If so, use the structured result of `assert_widget`/`wait_for` steps.
- `packages/flutterpilot_cli` smoke / test commands: check how they decide
  pass/fail.
- task 01's eval runner: not a consumer (it reads the agent's answer).

Name the consumer you switched in the PR.

## Tests

- Per tool: structured content present and matching the shape on pass, on
  fail, and on each error path you can reach in a unit test (follow
  `verification_test.dart`, `run_on_devices_test.dart`, `fleet_compare_test.dart`).
- Each result-rebuilding wrapper in `_registerTool()` keeps
  `structuredContent` (unit test with a fake callback returning structured
  content and an error that triggers the wrapper, or each wrapper's function
  tested directly).
- Text snapshots unchanged (C).
- If output schemas are declared: a test that every return path validates
  (mcp_dart would turn a mismatch into an error at runtime; catch it in tests).
- Fuzz test from task 02 still passes.
- e2e on a device; manually via `fp_bridge.dart`: `assert_widget` pass and
  fail, `wait_for` met and timed out. The bridge prints the raw JSON-RPC
  result; paste the `structuredContent` parts.

## Don't

- Don't change the text of any response.
- Don't add structured content to inspection tools.
- Don't put app data that the text masks (credentials, tokens) into
  structured content unmasked. Use the same redaction (`redaction.dart`).

## Done when

- [ ] Four tools return structured content on every path; wrappers keep it.
- [ ] Output-schema decision measured and justified.
- [ ] One in-repo consumer switched.
- [ ] Shapes documented in `TOOLS.generated.md`.
- [ ] Tests + e2e pass; README Definition of done.
