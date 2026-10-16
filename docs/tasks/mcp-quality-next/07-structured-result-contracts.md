# 07 — Machine-checked structured-result contracts
## Status, priority, and dependencies
Proposed; P1; after tasks 00–06. Estimated 2–4 days. Branch suggestion: `feat/mcp-result-contracts`.
## Problem and expected benefit
Programs should not infer truth from prose or accept drifting payloads. Strengthen existing structured results first, then add high-value coverage without uncontrolled schema/context growth.
## Verified starting points
- `packages/fp_server/lib/src/structured_results.dart` describes eight families in human-readable shape strings.
- It omits `outputSchema` intentionally to preserve list budgets, so the MCP SDK does not validate these payloads.
- `keepingStructured` preserves structured content through wrappers.
- `verify_feature` emits structured content only on finish; refusal/disconnection paths can differ from normal verdicts.
- `audit_screen_health` returns prose; route sweeps return counts even when visits/audits fail.
- Output schemas are optional, but advertising one commits to conformance on supported SDK/client protocols.
## Scope and non-goals
Add developer-side contract validation and a small structured-output pilot. Do not advertise output schemas everywhere, rewrite all prose, or double every response by default.
## Step-by-step implementation
1. Inventory success, failed check, invalid input, disconnected/unsupported, partial, and timeout/uncertain variants. Separate “predicate false” from “could not evaluate.”
2. Define executable developer-side schemas/types for the eight current families. Use supported validation or complete focused type checks; shape strings are not executable schemas.
3. Preserve compatible fields. Use explicit variants/status or optional details for unavailable results; do not fabricate counts/routes/success.
4. Add fixtures for every variant and redaction. Missing structured verdicts on documented verdict paths fail tests.
5. Prove wrappers preserve structured content and relevant metadata across image budgeting, hints, phone state, native crash, hang diagnosis, and result rebuilds.
6. Preserve structured fields in eval/CLI/bridge/fleet consumers that need them. Prefer typed facts over prose parsing, with fallback only for documented compatibility.
7. Pilot structured audit results: requested/visited/audited/failed/skipped counts, findings by category, restoration status, incomplete/loading flags. A failed route is not clean.
8. Distinguish preflight refusals from partially completed sweeps. Keep prose concise and machine details truthful.
9. Consider compact navigation results only if they eliminate real parsing: requested/current route, wait status, and completion/uncertainty.
10. Measure text duplication, structured payload size, and consumer behavior. Local contract validation must work without public `outputSchema`.
11. Pilot public schemas on one or two small stable families only after demonstrated client benefit. Test all variants and SDK behavior before registration.
12. Compare all profile budgets. Default to local schemas if public advertisement exceeds current limits; increases need explicit evidence/review, not automatic threshold changes.
13. Review the specification's text-serialization recommendation against actual clients. Choose a documented compatibility strategy from Inspector/eval evidence rather than blindly doubling output.
14. Generate documentation from authoritative contracts where feasible; preserve freshness tests and document shape versioning.
## Proposed file boundaries
- Modify `packages/fp_server/lib/src/structured_results.dart`, affected handlers/wrappers/consumers.
- Extend server `test/structured_results_test.dart`, registration/protocol tests, eval adapter tests, and audit/navigation cases.
- Update `packages/fp_server/tool/generate_tools_doc.dart` and generated docs through the generator.
- Public output-schema registration is a gated substep, not mandatory.
## Validation sequence
1. Validate all fixture variants, including failures and partial completion.
2. Inject structured/metadata markers through wrappers and assert preservation.
3. Compare typed facts with actual fixture state, not prose round-trips.
4. Exercise successful/failed sweeps, failed restoration, timeout, and zero-code.
5. Run Inspector/budget checks, full server tests, and device e2e.
## Acceptance criteria
- Current structured families have executable contracts and variant coverage.
- Unavailable evaluation cannot masquerade as passing assertions/clean screens.
- Audit results report completed work and failures honestly.
- Wrappers/adapters preserve facts and redaction.
- Public schema decisions include measured benefit and profile cost.
- No silent schema break or budget relaxation.
## Risks and rollback
Advertising schemas can make old error paths fail SDK validation. Start locally; make public advertisement independently reversible.
Avoid broad unions hiding inconsistent semantics. Revert new public shapes separately from validation/preservation fixes.
## Handoff
Leave contract fixtures, compatibility notes, consumer evidence, and per-profile size deltas for task 08.
