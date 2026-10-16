# 05 — Ten verified read-only, multi-step evaluations
## Status, priority, and dependencies
Proposed; P1; after tasks 00–04. Estimated 3–5 days. Branch suggestion: `test/mcp-read-only-evals`.
Two milestones: free deterministic suite preparation, then a separately approved paid baseline. Paid access must not block safety fixes or free verification.
## Problem and expected benefit
The existing 14 tasks exercise workflows including navigation, mocks, settings, profiling, and storage. Anthropic's ten-question pattern adds complementary discovery/inspection coverage only if fixtures are stable and the model cannot mutate them.
## Verified starting points
- `packages/fp_server/tool/eval/tasks.yaml` is the existing canonical YAML workflow suite.
- Exact/regex/numeric matching and expected-tool reporting already exist.
- Local lab apps are external repositories; task 00 makes identities reproducible.
- No expected answers for a new ten-case inspection suite were verified during planning.
## Scope and non-goals
Add a separate inspection suite, preserve workflows, and reuse the hardened runner. Do not relabel mutating tasks read-only or invent answers from source assumptions. XML is optional export, not a second canonical database.
## Ten candidate question designs
These are designs, not final entries. Refine against actual fixtures and verify answers through MCP before committing them.
1. Source attribution: discover a visible control, inspect source/style, and return the relative file building the control with a described role. Avoid absolute paths and unstable lines.
2. Form diagnosis: inspect a pre-opened form's disabled submission and validation; return the first blocking field label. Do not fill/submit.
3. Layout attribution: correlate errors and relevant widget constraints on a seeded overflow screen; return the responsible app widget type.
4. Error freshness: correlate a fixed post-reload exception with source attribution; return its type, excluding pre-reload records.
5. Network correlation: inspect fixed mock-backed requests and error evidence; return the status associated with a described loaded item's failure.
6. Database relation: discover schema and query read-only to identify a stable relation, such as the tag of the seeded note with the largest fixed attachment total.
7. State history: inspect seeded Bloc/Riverpod transitions plus current settings; return the value preceding the last relevant transition.
8. Preference consistency: compare rendered settings, observed state, and stored preferences; return the inconsistent key in a deliberately seeded fixture.
9. Accessibility attribution: correlate semantics/current-screen audit with inspection; return the source file of a control lacking an accessible name.
10. Zero-code discovery: inspect available tools and summary/tree; return the missing integration capability explaining why a requested interaction is unavailable, in an exact specified format.
Replace designs that prove single-call, ambiguous, unsupported, or unstable. Do not force redundant calls or penalize a future tool that answers in fewer calls.
## Step-by-step implementation
1. Define a separate suite ID/schema: fixture/scenario, question, answer, matcher, allowed modes, initial-state fingerprint, platforms, and verification evidence.
2. Prepare initial states in a trusted disposable-fixture setup phase. Navigation, reload, mocks, and seeded history may happen there, not during the model phase.
3. Freeze external data with mocks/local deterministic sources. Use fixed network/history evidence, not changing wall-clock answers or background refresh races.
4. Enforce argument-aware read-only policy from task 01. Deny navigation, settings, mocks, clears, scenario writes/loads, profiler actions/cycles, custom code, and mutating nested calls.
5. Prove forbidden calls are blocked even if setup permits destructive restoration. Hints and tool-name prefixes are not enforcement.
6. Give the answering model only discovered tools/guidance and the question. Withhold fixture source, `LAB.md`, answer keys, verifier transcripts, and author notes.
7. Solve each question manually through MCP. Record minimal sanitized calls/results, fixture identity, exact answer, and why alternatives are excluded.
8. Verify twice from independently reset state and in shuffled order. Check route/settings/storage invariants before/after the model phase.
9. Require exactly ten active verified cases with unambiguous answers, no inter-case dependency, and coverage of discovery, UI, diagnostics, state/storage, and zero-code.
10. Prefer scalar answers; specify path, case, whitespace, numeric, and enum normalization. Avoid permissive regexes accepting wrong answers.
11. Keep YAML canonical, proposed at `packages/fp_server/tool/eval/inspection_tasks.yaml`. Generate XML question/answer pairs only if external compatibility needs it; test escaping and consistency.
12. Add free suite validation and deterministic verifier checks. Separate device checks from fast unit tests and report actual coverage.
13. Request one paid canary with configured model/pricing. Inspect reset, policy, tool selection, caching, cost, and answer evidence.
14. After spend approval, run at least the existing three-repeat default per case for screening. Increase repeats for close decisions; do not overstate statistical confidence.
15. Review/accept a versioned baseline with all identities. Run original workflows separately so inspection gains cannot hide automation regressions.
## Proposed file boundaries
- Add canonical tasks, verifier metadata/evidence, and optional XML exporter under `packages/fp_server/tool/eval/`.
- Extend suite selection, loading, and policy tests from task 04.
- Test ten-case completeness, missing answers, invalid modes, shuffle independence, and export consistency.
- Lab source changes require separate fixture approval and manifest updates.
## Validation sequence
1. Validate suite structure, answer normalization, policy denial, and optional export using free unit tests.
2. Reproduce all ten manual MCP verifications twice with isolated reset and shuffled ordering.
3. Prove invariant checks detect intentional fixture mutation and reject the affected run.
4. Confirm the answering model cannot access answer/verifier files or privileged setup calls.
5. After separate spend approval, run the canary and repeated inspection/workflow suites; review identity and sample sizes before accepting the baseline.
## Acceptance criteria
- Ten questions have MCP-verified answers and reproducible initial states.
- No model-phase mutation reaches the app; policy violations visibly fail.
- Setup/teardown effects are isolated and reported separately.
- Answer keys are unavailable to the model.
- Free checks need no key; paid execution is explicitly approved.
- Any accepted paid baseline records suite/fixture/model/device/profile/protocol, usage, and sample sizes.
## Risks and rollback
Live timings, GC, pixel counts, and external data are unstable answer sources; prefer fixed identities/values. Fewer calls after improvement are a benefit.
Rollback suite selection independently and retain workflows.
## Handoff
Leave verified answers/evidence and either an accepted baseline or “paid baseline pending.” Task 08 cannot claim agent gains without comparable runs.
