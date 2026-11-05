# FlutterPilot reliability, speed, and design quality

## Context

FlutterPilot lets coding agents inspect and operate running Flutter apps through MCP, with optional SDK and plugin integrations. Its users include developers integrating it into an existing app and agents trying to understand, change, and verify that app. The repository already includes app discovery, diagnostics, workflows, agent guidance, an end-user skill, real-app fixtures, and benchmarks.

The user reports commands that were unreachable or produced read issues and wants quicker, more autonomous work and higher-quality design outcomes. These reports are important signals; the specific commands, clients, failures, frequency, and affected project have not yet been established. They should be treated as investigation priorities, not attributed to a particular bug without reproduction.

## Gap

The experience spans client configuration, server startup, app discovery, SDK registration, plugin readiness, tool visibility, action execution, and verification. A failure at any layer can look like “the command doesn't work.” Dynamic tool visibility can also interact with clients that do not refresh their tool list. Some capabilities require an SDK, a plugin, a compatible target, or a specific profile. These distinctions must be understandable to both the agent and developer.

The existing skill teaches operation, but operating a UI successfully does not by itself produce a distinctive, coherent design. FlutterPilot can collect visual and runtime evidence for a design critique; design judgment still requires context, interpretation, and human evaluation. Product superiority has not been demonstrated against competitors or in representative user studies.

## Opportunity

Make FlutterPilot the dependable feedback loop for Flutter agents: discover what is possible, act with minimal back-and-forth, see what actually happened, recover from failures, and review the result against the product's intent. First prove the loop works across real projects and clients, then deepen design and autonomous workflows on that foundation.

## Goals

- Increase the share of real tasks completed correctly without human intervention.
- Reduce setup failures, unreachable tools, misleading successes, duplicate calls, elapsed time, and token cost.
- Make every unsupported capability and failed read explain its cause and recovery path.
- Help agents produce interfaces that fit their product, audience, platform, and existing design language.
- Preserve user control, privacy, compatibility, and honest reporting.

## Constraints

- No reproducible session or client-specific logs have been supplied for the reported failures.
- Some tools require the SDK, plugins, debug/profile builds, device capabilities, or destructive-operation permission.
- Dynamic listing depends on client behavior; static listing exposes unavailable tools but must explain why they cannot run.
- Saved benchmarks are environment-specific. The Windows startup investigation reports AOT MCP readiness of 66 ms with no app and 61 ms with an unreachable endpoint after the startup reorder; this does not establish end-to-end task speed on other machines.
- Evaluation cost, engineering capacity, target clients, and business constraints are unknown. Paid model evaluations need a budget decision.

## Guiding Principles

1. Evidence before claims: distinguish observed behavior, hypotheses, and untested ideas.
2. A result should say what happened, what is uncertain, and what to do next.
3. Prefer fewer agent turns and scoped data, while retaining meaningful primitives and compatibility.
4. Design quality comes from product context, visual inspection, and iteration, not a universal style or a blacklist alone.

## Key Assumptions & Open Questions

- Which client, operating system, Flutter version, app configuration, tool name, and exact error reproduce each reported issue?
- Does the failure occur at installation, tool discovery, connection, runtime read, plugin registration, or after a hot reload?
- Which tasks are most valuable: implementing UI, debugging, QA, accessibility, visual polish, or performance investigation?
- Which clients and Flutter targets are actually used most? How often are apps zero-code, SDK-enabled, or plugin-enabled?
- Which design references, product constraints, and quality standards should the agent follow? Can reviewers compare results blind?
- What is the baseline for task success, latency, call count, token cost, user intervention, and false success?
- Which competing tools and workflows do users actually consider? Market leadership needs current comparative research and user evidence.

## Proposed Scope (Phase 1)

### 1. Reproduce and fix reachability and reads

- Collect sanitized, opt-in diagnostic bundles: client and versions, project/target type, installed server build identity, profile, connection stage, tool visibility, plugin status, timings, error category, and correlation IDs. Exclude source, UI text, credentials, request bodies, and paths by default; preview the bundle before sharing.
- Create a capability matrix for each tool: listed versus callable, prerequisites, unsupported targets, permissions, readiness, source of the data, and known client refresh behavior. Expose a compact capability explanation both through the CLI doctor and an agent-facing discovery path, reusing existing facilities where possible.
- Trace one request across client → MCP → server → VM service → SDK/plugin, with bounded per-stage timeouts and explicit categories such as not configured, server stale, no app, connecting, SDK missing, plugin missing, unsupported target, permission denied, stale isolate, timeout, partial result, and malformed response.
- Audit client compatibility, including tool-list refresh and reconnect; choose a documented static-tool fallback per affected client if evidence warrants it. Never make an unavailable tool look successfully callable.
- Exercise installation and discovery in clean projects, monorepos, multiple running apps, IDE-launched apps, devices, hot restart, reconnect, and client restarts. Verify tool inventory and a representative read and action end to end.
- Define bounded retries only for reads known to be safe; after a timed-out write, report uncertain outcome and inspect state before attempting a repeat.
- Make `fp doctor` actionable: show the precise failed layer, client config and binary version, a safe fix, and a way to recheck. Prevent accidental connection to the wrong project or device.
- Audit documentation against actual flags and permission behavior. For example, the server README currently describes `--uri` as required and separately describes destructive SQL being enabled; the top-level README describes automatic discovery and says SQL remains read-only. Verify implementation and resolve discrepancies rather than assuming either text is authoritative.

### 2. Measure and shorten real work

- Establish an end-to-end baseline on representative Flutter tasks: connect, discover, inspect, modify, reload, verify, and recover. Include cold and warm runs, device and build mode, p50/p95, failures, calls, bytes/tokens, and user interventions. Retain timeouts in results.
- Build a profiler for the critical path: app discovery, VM connection, screenshot capture and transfer, tree/semantics reads, UI settling, reload, analyzer fallback, and agent decision time. Optimize the largest measured costs first.
- Prefer one scoped observation containing the relevant view, actionable elements, current errors, and optional screenshot over repeated broad reads where it is demonstrably useful. Support bounds, filters, limits, pagination, incremental diffs, and explicit truncation.
- Return useful post-action evidence, change summaries, and readiness signals so the agent need not request the same tree or screenshot again. Keep full reads available when needed.
- Use event-driven waits and condition-based settling with explicit deadlines; avoid fixed sleeps and unbounded polling. Cache only where invalidation after reload, navigation, state changes, or reconnect is reliable.
- Support safe batching of independent reads and preflight workflows before execution. Preserve per-step results, ordering, cancellation, and partial-failure visibility. Do not blindly replay mutations.
- Investigate screenshot downscaling, regions, image encoding, and detail-on-demand against visual fidelity. Do not optimize away evidence needed to detect layout defects.
- Make the installed binary identity and update path clear; a fast AOT build is useful only if the client is running the current server.

### 3. Give agents a better operating loop

- Make the existing generated FlutterPilot skill the canonical starting point; audit its claims and examples against the live schemas. Load compact operational guidance first and task-specific detail on demand.
- Teach capability-first planning, selecting the smallest useful observation, interpreting action responses, explicit assertions, safe recovery, and knowing when to stop. Avoid obligatory screenshots and full-tree reads after every action.
- Add reusable workflows for UI change verification, form journeys, startup failures, network/offline behavior, layout/accessibility sweeps, and profiling. Treat these as composable recipes with evidence and bounded steps, not new opaque tools by default.
- Add a task ledger with intended checks, observations, unresolved issues, and confidence. When an agent is interrupted, allow it to resume from verified state rather than repeating every step.
- Develop an optional autonomous fix loop: reproduce → collect evidence → locate source → make a bounded change → reload → verify the original behavior and regressions → report. Gate app-data mutations and external effects according to existing permissions and the user's instructions.
- Provide outcome-aware recovery for stale selectors, changed routes, transient disconnections, and target ambiguity; stop and explain when the next action is unsafe or unverified.
- Generate useful reproduction artifacts: minimal action sequence, environment, expected versus observed result, relevant screenshot or trace, with redaction and explicit inclusion controls.

### 4. Add taste as a practical design-review capability

- Extend the existing skill or add an optional specialized companion after testing discoverability. Start by understanding the product, audience, task, existing components, brand, platform conventions, constraints, and any references.
- Require an actual before/after visual review on relevant devices and states when possible. Inspect hierarchy, spacing, type, contrast, density, content, interaction feedback, consistency, accessibility, and motion. Examine empty, loading, error, long-content, large-text, keyboard, and narrow-window states when relevant.
- Give the agent a critique-and-revise loop: identify a few consequential weaknesses, explain the intended improvement, implement, inspect the rendered result, and revise until the task's acceptance criteria are met or a limit is reached.
- Encourage intentional, product-specific choices: coherent typography and spacing, appropriate information density, meaningful visual emphasis, credible content, and distinctive details that serve the task. Avoid generic dashboards, arbitrary gradients, ornamental cards, excessive rounded rectangles, filler copy, and unnecessary animations when they do not suit the product. These are review prompts, not automatic prohibitions.
- Use established app tokens and components by default; propose a deliberate divergence only when supported by product context. Respect platform and accessibility needs, reduced motion, and user preferences.
- Combine automated checks (overflow, contrast where measurable, touch targets, semantics and screenshots) with model and human visual review. Separate objective defects from subjective critique; don't claim a taste score proves design quality.
- Evaluate with blind human comparisons on a diverse set of real tasks, including existing-brand constraints, enterprise density, consumer polish, accessibility, and small screens. Measure task suitability and coherence alongside aesthetic preference.

### 5. Simplify and maintain

- Inventory tools, profiles, plugins, guidance, examples, and docs; identify duplicate paths, stale names, low-value output, unmaintained integrations, and feature combinations that cannot be verified.
- Keep capabilities users need. Consolidate only after task traces show confusion or duplication; compare task success before and after. Publish migration guidance and a deprecation window for public changes.
- Replace blanket claims such as “zero friction” with verified support statements and a versioned compatibility matrix.
- Improve generated documentation consistency and executable examples; keep one authoritative source for schemas and agent guidance.
- Make unsupported and experimental capabilities visible, with ownership and tests; retire truly unmaintained functionality only after reviewing usage and alternatives.

### 6. Build a credible evaluation and product loop

- Assemble representative real-app tasks and failure fixtures, including read failures, stale binaries, dynamic discovery, multiple devices, and design improvements. Run deterministic protocol and real-device checks separately from model-driven evaluations.
- Track task success with independent verification, false-success rate, recovery rate, time to first useful result, end-to-end duration, number of calls, token cost, setup completion, and user intervention. Report distributions and sample sizes, not just averages.
- Compare against the current release and common alternative workflows under the same tasks, constraints, devices, and model budgets. Do not claim market leadership from feature counts.
- Collect opt-in metadata only, with a clear off switch, no secrets or app content by default, and deletion/retention controls. Complement it with developer interviews and consented session reviews.
- Use support reports to build regression cases. Publish a compatibility and reliability scorecard, and triage failures by user impact and frequency.

### Suggested sequence and decision gates

1. **Investigate:** reproduce the reported failures and establish a task baseline. Deliver a ranked failure inventory and compatibility matrix.
2. **Restore trust:** fix the highest-impact reachability and read failures; validate with real clients and apps, including reconnect and failure recovery.
3. **Speed up the loop:** measure before/after end-to-end work; ship the biggest safe reductions in latency, calls, and unnecessary output.
4. **Improve agent behavior:** refine the existing skill and add focused workflows; use comparable task evaluations to decide what helps.
5. **Develop taste:** prototype a design-review workflow, compare against existing guidance with blinded human review, and iterate before claiming improvement.
6. **Prune and expand:** deprecate evidenced duplication, then prioritize additional integrations or features from validated demand.

Each phase can run in small increments. The first release gate is reproducible improvement in task completion and truthful failure reporting; performance and design claims require their own comparable evidence. No implementation or measurements are claimed by this brief.
