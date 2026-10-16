# 02 — Nested argument contracts and all-step preflight
## Status, priority, and dependencies
Proposed; P0; after tasks 00–01. Estimated 2–4 days. Branch suggestion: `fix/mcp-composite-preflight`.
## Problem and expected benefit
A composite can run earlier actions before encountering a malformed later step. The in-app optimization and server fallback do not share complete argument validation. Reject invalid plans before acting, while distinguishing runtime failure from invalid input.
## Verified starting points
- `packages/fp_server/lib/src/arg_coercion.dart` handles types and required properties, but is not a full JSON Schema validator.
- `execute_action_chain` advertises `steps` as an array of generic objects.
- Its preflight checks shape, allowed tools, and profile availability, then may send simple taps/text directly to `ext.flutterpilot.executeActionChain`.
- The fallback invokes `_toolCallbacks` per step; a later argument refusal can happen after earlier actions.
- `run_on_devices`, `profile_action`, and leak-check `cycle` have separate nested-call parsing/checks.
- Existing tests distinguish strict direct MCP schema validation from permissive internal coercion. Preserve that distinction deliberately.
## Scope and non-goals
Create reusable nested-call preflight and improve compact public schemas. Do not flatten meaningful forms, action arrays, arbitrary state, or channel payloads into strings. Do not promise rollback when a valid action fails at runtime.
## Step-by-step implementation
1. Specify a normalized step contract: `tool` plus an optional object `arguments`. Preserve documented retired-step translations and aliases before validation.
2. Specify both boundaries: direct `tools/call` follows published JSON types; nested calls may apply existing unambiguous coercions before canonical validation. A malformed JSON string is not a valid object.
3. Add a compact shared step-envelope schema with required `tool`, typed `arguments`, and reviewed unknown-field behavior. Keep each tool's argument constraints authoritative in its registered schema instead of copying every schema into every composite.
4. Extend or replace internal validation to enforce schema features actually used: nested required fields, primitive array items, enums, numeric bounds, and additional properties. Evaluate Dart SDK validation reuse before adding dependencies.
5. Inventory unsupported JSON Schema constructs. Fail development-time contract checks or provide explicit exceptions rather than pretending to implement all of JSON Schema.
6. Add shared preflight that normalizes and validates every step, checks allowed tool families, profile/capability availability, and applicable permission/effect constraints, then returns canonical arguments.
7. Run preflight before SDK batch dispatch, CPU profiling, warm-up cycles, device fan-out, navigation, or text entry. Invalid step N means zero executed steps on every device.
8. Feed only canonical steps into the in-app optimization. If an option cannot be preserved by the fast path, use fallback; never silently drop it.
9. Apply the same preflight to fallback execution, `run_on_devices`, `profile_action`, and leak-check cycles. Validate all steps, not a sample.
10. Return actionable errors with paths such as `steps[2].arguments.key`, expected shape, and a short example. Redact values; never echo entire possible-secret payloads.
11. Distinguish input refusal from runtime partial execution. Invalid input says zero executed; runtime failures truthfully report completed steps and uncertain outcomes, without claiming rollback.
12. Test valid-first/invalid-last actions, fast-path unknown arguments, stringified nested maps, scalar array items, null required fields, aliases, oversized batches, and forbidden/profile-hidden steps.
## Proposed file boundaries
- Modify `packages/fp_server/lib/src/action_chain.dart`, `arg_coercion.dart`, and argument-gate plumbing in `lib/fp_server.dart`.
- Update composite handlers in server `lib/src/tools/ui_automation_tools.dart`, `app_inspection_tools.dart`, and `devtools_tools.dart`.
- Extend server `test/action_chain_test.dart`, `arg_coercion_test.dart`, `tool_argument_fuzz_test.dart`, and `run_on_devices_test.dart`; add focused fast-path tests.
- Change SDK handlers only if server validation cannot preserve the contract; require corresponding SDK tests.
## Validation sequence
1. Use injected action counters to prove invalid later steps execute zero earlier steps on every path.
2. Run valid fast/fallback parity cases with identical final state and verdicts.
3. Run malformed direct and nested calls over real stdio; document intentional coercion differences.
4. Check generated docs and schema-size budgets, including core.
5. Run full server tests and device e2e with successful and runtime-failing batches.
## Acceptance criteria
- Every composite validates all submitted steps before acting.
- Refusals name the offending path and never suggest blindly retrying invalid input.
- Fast execution cannot bypass argument, type, capability, or permission checks.
- Supported canonical inputs, aliases, and intentional structured values remain supported.
- Runtime partial completion is reported honestly.
- No enormous union schema or silent budget increase is required.
## Risks and rollback
Stricter validation may reject previously ignored inputs; document explicit corrections. Preflight cannot guarantee the app remains unchanged before execution, so runtime guards remain necessary.
Rollback handler integration independently of the shared validator while retaining regression tests.
## Handoff
Provide the direct/nested compatibility matrix and malformed-call fixtures. Task 03 replays representative cases through the official Inspector.
