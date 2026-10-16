# 06 — Focused, coherent, bounded resource reads
## Status, priority, and dependencies
Proposed; P1; after tasks 00–05 in the recommended sequence. Estimated 2–3 days. Branch suggestion: `perf/mcp-resource-read-plans`.
## Problem and expected benefit
Resources should provide focused context without unrelated hidden work. Even fleet reads currently gather app snapshot, errors, and widget tree. Reduce VM calls/failure coupling and make each response belong to one device/connection generation.
## Verified starting points
- `_readResource` and live `readResourceForTest` in `packages/fp_server/lib/src/resources.dart` call `_liveResourceData()` without identifying the requested resource.
- `_liveResourceData()` sequentially reads `getAppSnapshot`, `getErrors`, and `getWidgetTree`.
- Rendering `flutterpilot://devices` uses fleet and connection/platform fields, not the fetched widget tree.
- Fixed resources/templates and subscriptions already exist.
- `_extensionData` converts errors to null; missing support and transient failures need explicit treatment.
## Scope and non-goals
Optimize existing URIs without adding tools or migrating clients. Prefer targeted reads over global caching. Attached resource contents still consume model context, despite not adding tool definitions.
## Step-by-step implementation
1. Map dependencies for every fixed resource/template, including freshness/error-split requirements. Preserve existing field meanings.
2. Record current VM-call counts and response sizes with injected counters. Use a large-tree fixture rather than flaky timing as the primary regression test.
3. Replace gather-everything with resource-specific read plans or focused loaders.
4. Make `flutterpilot://devices` use zero app VM calls; derive connection/platform fields from captured fleet/context state.
5. Fetch only summary dependencies. Keep accurate post-reload error count and route/lifecycle/build facts, but never build a summary's widget tree.
6. Fetch errors/logs/tree independently. Logs must not fail or grow because an unrelated tree call is slow.
7. Pin active device and connection generation at read start. Re-check after awaits; report context change rather than mixing apps.
8. Preserve zero-code fallbacks, missing-plugin behavior, and no-app shapes. Distinguish unsupported data from healthy empty results when extensions fail.
9. Keep template scoping; test encoded keys/routes with spaces, slashes, quotes, and Unicode. Never navigate merely to satisfy a resource read.
10. Apply redaction and bounded rendering to fixed and templated outputs. Keep JSON parseable under bounds, using item-aware limits/truncation metadata instead of cutting serialized JSON.
11. Preserve subscribe/unsubscribe and freshness behavior. Route/reload/device changes affect relevant context; avoid notification storms.
12. Avoid persistent caching initially. If request-local deduplication proves useful, scope to device/generation/read and test invalidation.
13. Compare call counts and repeated same-device latency samples. Document limits, unavailable data, and on-demand costs honestly.
## Proposed file boundaries
- Modify `packages/fp_server/lib/src/resources.dart`; extract helpers only if needed.
- Extend `packages/fp_server/test/mcp_resources_test.dart` and protocol tests.
- Add fake-extension counters and switch/reconnect fault injection.
- Change guidance sources only if client usage changes, then regenerate.
## Validation sequence
1. Assert allowed/forbidden extension calls per URI; devices must make zero.
2. Inject a failing tree and prove summary/errors/logs remain independent.
3. Switch/reconnect between awaited reads and assert no mixed response.
4. Cover no-app, zero-code, templates, redaction, bounds, and subscriptions.
5. Run full server tests and connected e2e; report before/after counts and samples.
## Acceptance criteria
- No resource fetches a widget tree unless needed.
- Fleet reads use zero app VM calls.
- Responses belong to one device/generation or report changed context.
- Errors are not silently presented as clean empty state.
- Existing URIs/normal response meanings remain compatible.
- JSON stays parseable and secret-safe when bounded.
- No new tool definitions or unjustified persistent cache.
## Risks and rollback
Shared gathering hides dependencies such as error freshness; pin semantics before optimizing. Preserve injected-data tests without bypassing live behavior checks.
Rollback individual loaders independently. Keep call-count tests and justify any necessary extra dependency.
## Handoff
Provide dependency maps, call counts, bounds/redaction evidence, and same-device latency comparisons. Task 07 reuses coherent data for contracts.
