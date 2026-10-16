# 01 — Truthful tool effects and retry safety
## Status, priority, and dependencies
Proposed; P0; after task 00. Estimated 2–4 days. Branch suggestion: `fix/mcp-effects-and-retries`.
## Problem and expected benefit
A client can make unsafe parallelization or confirmation decisions from inaccurate hints. Repeating an action after a lost response can duplicate effects. FlutterPilot needs conservative advertised hints and explicit runtime retry rules, not assumptions inferred from tool or extension names.
## Verified starting points
- `packages/fp_server/lib/src/tool_annotations.dart` marks `audit_screen_health` as `reads`, which also makes it idempotent.
- `packages/fp_server/lib/src/tools/ui_automation_tools.dart` navigates through routes when `audit_screen_health(routes: ...)` is called. Returning to the first route does not undo requests, listeners, or other navigation effects.
- `get_state(clear: true)`, `get_debug_logs(clear: true)`, and `get_http_profile(clear: true)` have diagnostic-clearing modes. Those deserve an explicit observation-versus-diagnostic-state distinction.
- `_isReadOnlyExtension` in `packages/fp_server/lib/fp_server.dart` relies on prefixes including `get`, `audit`, `profile`, and `generate`; its result affects scheduling and retries.
- Actual destructive permission checks exist inside relevant handlers. An annotation is not an authorization boundary.
## Scope and non-goals
Correct effect modeling and retry eligibility while preserving existing names/signatures. Do not make all diagnostics destructive, add an automatic permission bypass, or claim every UI action can be reversed.
## Step-by-step implementation
1. Inventory every registered tool and all mode-changing arguments. Record app-state changes, FlutterPilot diagnostic-state changes, filesystem writes, external-service effects, and replay safety separately.
2. Define an internal effect record with conservative advertised hints and an argument-aware runtime classification. Do not infer `idempotent` merely from an observational name or infer retry safety from idempotence alone.
3. Classify `audit_screen_health` conservatively as acting at the public tool level while retaining its current-screen observation mode internally. Disclose route sweeps and best-effort restoration in its description.
4. Review all diagnostic clear/reset modes, scenario list/save/load, screenshot comparison/save, memory sampling/cycles, custom code, mocks, and multi-device composites. Include indirect external effects and unknown user callbacks.
5. Define what diagnostic clearing means for read-only policy and concurrency. Advertise the strongest supported effect conservatively; let explicit internal policy recognize safe argument combinations.
6. Audit idempotent and open-world hints. Document the chosen trust boundary for UI actions that can trigger network calls; do not set closed-world merely because FlutterPilot talks to a local VM.
7. Replace extension-prefix retry decisions with reviewed metadata or explicit call-site policy. Unknown extensions default to no automatic replay. Mark clear/reset modes non-replayable even if they do not change app data.
8. Keep scheduler classification, public annotations, and destructive authorization separate but test consistency. Do not introduce a reentrant tool-wide lock without proving nested composite execution cannot deadlock.
9. Test response-loss/reconnect with a fake extension that counts executions: safe reads may retry; actions, clears, and unknown operations execute at most once and report uncertainty.
10. Cover pinned non-active devices and connection generations so reconnecting one device never retries against another.
11. Require explicit registration coverage for every tool and every server-used extension eligible for retry. Exceptions need a reason and regression test.
12. Update generated tool documentation and contributor notes. Explain that hints do not enforce permission and a timeout may leave an action applied.
## Proposed file boundaries
- Modify `packages/fp_server/lib/src/tool_annotations.dart`, effect/retry call sites in `lib/fp_server.dart`, and affected descriptions in `lib/src/tools/`.
- Add a focused effect-policy module if separating metadata simplifies testing.
- Extend server `test/tool_registration_test.dart`, `operation_scheduler_test.dart`, `vm_connection_test.dart`, and effect/retry tests.
- Do not redesign the scheduler or add new tools without a separately reviewed regression.
## Validation sequence
1. Unit-test every mixed mode, unknown-operation default, destructive denial, and exact-once action counter.
2. Run protocol annotation checks and the full server suite.
3. Regenerate tools documentation and verify tool-list budgets.
4. On a disposable app, sweep two routes, read/clear diagnostics, and simulate a lost action response; check actual state before retrying.
5. Run device e2e for changed runtime behavior.
## Acceptance criteria
- No navigational route sweep is advertised as purely read-only.
- Every public tool has four reviewed hints; destructive operations remain permission-gated.
- Retrying a diagnostic clear cannot silently erase newly collected evidence.
- Unknown or acting extensions are never replayed solely because of their name.
- Non-active-device retries preserve device identity and generation.
- Compatibility and context-budget effects are documented; tool names remain stable.
## Risks and rollback
Conservative hints may cause more client confirmation. Avoid broad execution serialization here: it expands scope and risks deadlocks.
Rollback metadata and retry changes independently if necessary, but do not restore a known misleading hint as the long-term resolution.
## Handoff
Provide the effect inventory, rationale for exceptions, failure-injection evidence, and argument-aware policy interface. Task 05 uses that policy for read-only evaluations.
