# Developing FlutterPilot's MCP surface

How to change a tool, resource, prompt, guidance text or profile in
`packages/fp_server/` — the research, the contracts, the commands, and the
evidence a change has to carry. It is one Dart-specific recipe; there is no
second maintenance procedure.

This page is a contributor recipe. The agent-facing texts the server ships
(`serverInstructions`, the `flutterpilot_guide` prompt, `skills/flutterpilot/SKILL.md`)
are **generated** from `packages/fp_server/guidance/` — see
[Agent-facing text](#agent-facing-text-is-generated). The tool reference is
**generated** from the running registration — see
[The tool reference is generated](#the-tool-reference-is-generated).

---

## 1. Start from a hypothesis, not a merge count

Tool count is a means, not the goal. Optimise task success and total session
cost, and prefer, in order:

1. a **description or example** change,
2. **existing batching** (`execute_action_chain`, `run_on_devices`,
   `fill_form(submitWith:)`, `tap_widget(waitFor:)`),
3. a **scoped MCP resource** or prompt,
4. a **new tool** — last, and only for a capability nothing else reaches.

Write down the hypothesis before coding: what a client does wrong today, and
which number should move (calls, tokens, error rate, response bytes). One
hypothesis per change; do not mix a schema change with a description rewrite.

**Do not** merge distinct permission classes, remove useful primitives to lower
a count, or install a redundant skill. A count reduction that harms discovery
or recovery is cosmetic and is rejected.

## 2. Research before you design

- Read the generated inventory
  ([`TOOLS.generated.md`](../TOOLS.generated.md)) rather than a remembered list.
- Check what already exists: `grep` the name in `lib/src/tools/`, and check
  `lib/src/tool_profiles.dart`, `lib/src/plugin_tools.dart`,
  `lib/src/zero_code.dart` and `lib/src/build_mode.dart` for gating.
- For anything element-wise, use **existing structured results** instead of
  parsing prose: `lib/src/structured_results.dart` is the contract layer (see
  [Argument, effect and result contracts](#4-argument-effect-and-result-contracts)).
- Measure the current surface: `dart run
  packages/fp_server/tool/tool_list_report.dart` (text) or `--json` (per profile
  and per tool: chars, UTF-8 bytes, wire bytes, estimated tokens).
- Decide the **unit**: characters vs UTF-8 bytes vs full-wire bytes vs billed
  tokens. Never compare two different units and call it a gain.

## 3. Tool, resource or prompt?

- **Tool** — a new *capability* the model must choose. It costs `tools/list`
  bytes on every turn and competes for selection with the existing tools.
- **Resource** — live state a resource-aware client attaches and re-reads
  without a tool call (`lib/src/resources.dart`). It adds nothing to
  `tools/list` but is not globally free context. Read only the app extensions
  the resource needs (`_resourceExtensions`), and answer with no app connected
  rather than throwing.
- **Prompt** — the right tool *sequence* for a named task
  (`lib/src/prompts.dart`). Use one instead of teaching the order in
  `serverInstructions`.

Prefer resources and prompts when the user's need is state or a recipe, not a
one-shot action.

## 4. Argument, effect and result contracts

Every tool has three contracts; a change to any of them is a compatibility
decision, not an implementation detail.

**Arguments** (`lib/src/arg_coercion.dart`, `lib/src/action_chain.dart`)

- A tool's own schema stays authoritative for its own arguments.
- Composites (`execute_action_chain`, `run_on_devices`, `get_memory_details`
  `cycle`, `profile_action`) share the compact step envelope
  `{"tool": <name>, "arguments": <object>}` (`compositeStepSchema()`); they do
  not copy another tool's schema.
- `preflightStep` / `preflightChain` run **every** step through the same checks
  a direct `tools/call` runs — retired-name translation, family, availability,
  profile, then the schema gate — **before** the composite does any work, so an
  invalid plan executes zero steps. Nested problems are reported by their full
  path (`steps[2].arguments.key`).
- A cross-field check that lives only in a callback (e.g. "gesture: swipe needs
  direction") is *not* caught by preflight; do not assume it is. Express it in
  the schema when it must be a preflight guarantee.

**Effects** (`lib/src/effect_policy.dart`)

- Add or change an effect with `ToolEffect` on registration, and add any
  service-extension call to the reviewed inventory. `mutating` and `replaySafe`
  are **independent** facts: a call can be a read that must not be replayed (a
  diagnostic clear) or an action that is safe to retry.
- Anything unlisted is `known: false` and treated conservatively (serialised,
  never replayed). A clear-capable tool advertises the strongest effect
  (`acts`) even though its non-clearing form is a read.
- The open-world boundary is the app's reach, not the server's local VM: any
  tool that can drive the app or run its code is open-world.
- `test/effect_policy_test.dart` fails when an `ext.…` name in `lib/` is missing
  from the inventory.

**Results** (`lib/src/structured_results.dart`)

- A `structuredContent` twin is described by a `StructuredSpec` in
  `structuredContracts`, not by a hand-written shape string. The documented
  shape in `TOOLS.generated.md` is **rendered from the contract**
  (`structuredShapes`), so it cannot drift.
- `structuredProblems(name, payload)` validates a payload at its path. Add a
  representative fixture to `validStructuredFixtures` in
  `test/structured_results_test.dart`.
- Separate *"the predicate is false"* from *"we could not evaluate"* with the
  optional `status` field (`ok`/`partial`/`refused`/`unavailable`). An empty
  list must never read as a clean one.
- Do **not** advertise a public MCP `outputSchema` without client evidence: that
  commits old error paths to SDK-side validation and grows `tools/list`. The
  local contracts are the default deliverable.

## 5. The tool reference is generated

`TOOLS.generated.md` (repo root) is rendered from the running server's
registration by `tool/generate_tools_doc.dart`. After any change to a tool's
name, description, schema, effect or structured shape, regenerate it **from the
repository root**:

```bash
dart run packages/fp_server/tool/generate_tools_doc.dart
```

`test/tools_doc_generated_test.dart` fails when the committed file is not what
the registration renders, so a stale doc cannot survive. Never hand-edit
`TOOLS.generated.md`.

## 6. Agent-facing text is generated

`guidance/instructions.md`, `guidance/guide.md` and `guidance/skill.md` are the
one source for `serverInstructions`, the `flutterpilot_guide` prompt and
`skills/flutterpilot/SKILL.md`. A marker on its own, `<!-- include: name -->`,
expands `guidance/partials/name.md` one level deep.

```bash
cd packages/fp_server
dart run tool/generate_guidance.dart
```

`test/guidance_generated_test.dart` fails when a generated file is stale.
Change a guidance source **only when client usage changes**, keep the three
texts consistent, and do not stuff every tool detail into the always-loaded
instructions — per-tool detail belongs in the tool description.

## 7. Test commands

```bash
# Analyse (must be clean)
cd packages/fp_server && dart analyze

# One test file while iterating
cd packages/fp_server && dart test test/tool_registration_test.dart

# The whole server package
cd packages/fp_server && dart test

# The monorepo aggregate gate (portable, fail-closed)
melos run test            # == dart tool/package_test_runner.dart
```

Format only the files you touched: `dart format <files>`.

The gates most often relevant to an MCP-surface change:

| Area | Test |
|---|---|
| Tool count, size, descriptions, annotations, instructions, effects | `test/tool_registration_test.dart` |
| Per-profile cost and the estimate | `test/tool_list_report_test.dart` |
| Effect/replay inventory coverage | `test/effect_policy_test.dart` |
| Nested argument contracts and composite preflight | `test/action_chain_test.dart`, `test/composite_preflight_test.dart`, `test/arg_coercion_test.dart` |
| Structured shapes and every verdict variant | `test/structured_results_test.dart` |
| Resources (per-URI app calls, pinning, bounds) | `test/mcp_resources_test.dart` |
| Protocol hygiene and the raw wire | `test/mcp_protocol_compliance_test.dart` |
| Generated docs freshness | `test/tools_doc_generated_test.dart`, `test/guidance_generated_test.dart`, `test/docs_freshness_test.dart` |

## 8. Official Inspector

The pinned official MCP Inspector is the independent client check that the wire
is still what a real client expects:

```bash
dart run packages/fp_server/tool/inspector/inspector_cli.dart
```

See `packages/fp_server/tool/inspector/README.md` for install, the probe list
and the connected-fixture run. It is a protocol/negotiation/refusal check; a
network failure is a setup failure, never a server pass.

## 9. Authoring an evaluation

The eval runner lives in `packages/fp_server/tool/eval/` (see its `README.md`).

- **Fixtures** are declared in `tool/eval/fixtures/manifest.json` with app id,
  source location, exact git revision, license, required plugins, build mode and
  scenario checksums. `tool/eval/check_fixtures.dart` is a read-only preflight;
  rewire or re-pin a fixture only as an explicitly approved change, and update
  the manifest in the same commit.
- **Workflow tasks** and the **inspection questions**
  (`tool/eval/inspection_tasks.yaml`) are separate suites. An inspection
  question must carry an `answer`, `verified: true` and `evidence`; a proposed
  answer can never be scored.
- A **run identity** (`tool/eval/src/identity.dart`) records model, device,
  platform, build mode, SDK versions, task-suite hash, per-fixture hashes,
  runner policy and pricing version. `compareReports` refuses mismatched or v1
  reports.
- Read-only suites use `ReadOnlyPolicyClient`; never run a mutating tool in an
  inspection suite.
- Paid runs need an explicit price in `tool/eval/pricing.json` and separate
  spend approval. A spend guard cannot undo an in-flight charge.

## 10. Budgets

`test/tool_registration_test.dart` holds the per-profile `tools/list` size
budgets and `test/tool_list_report_test.dart` holds tighter ceilings. A round
may **lower** a budget; it may not raise one to fit a change. Prefer trimming a
redundant example over raising a number, and keep the legacy character measure
(`toolListChars`) so a baseline stays comparable — see
`lib/src/tool_list_bytes.dart`.

## 11. Security and privacy

- All logging goes to **stderr**, never `stdout` (stdout is JSON-RPC only).
- Credentials are masked in every tool response (`Redaction`). Redact new string
  fields, and keep encoded JSON valid when redacting structured values.
- Destructive tools (`ToolEffect.destructive`) must stay behind
  `--allow-destructive`. Storage writes, clears and running app code are
  destructive.
- Telemetry is **metadata-only** (tool names, timings, outcomes) with
  `--no-call-log`; never turn it into payload collection.
- Bound every response (item caps and a byte cap) so one large app screen cannot
  blow up a session.

## 12. Compatibility

- Additive is safe: a new optional field, a new enum value, a new tool.
- Renaming or removing a tool/scheme needs migration: a retired-name translation
  (`lib/src/retired_tools.dart`), refusal guidance, regenerated references, a
  version bump and a client test. Do it only when evidence demands it, and as a
  separately reviewed change.
- Consumers read structured values, not prose (the fleet-comparison consumer,
  the eval adapter, the shell bridge). Keep new machine data in
  `structuredContent`.

## 13. Required evidence

An accepted change carries:

- a **hypothesis** and the **metric** it targets;
- **free gates** — schema/protocol/effect/contract/guidance/budget/Inspector —
  passing with equivalent fixtures;
- a **comparable** before/after report for any claim about model behaviour
  (same model, device, platform, build mode, task suite, fixtures and policy),
  or an explicit **inconclusive** label when the sample is too small or the run
  was not approved;
- no safety regression, no newly failing reliable task, and no unreviewed budget
  growth;
- regenerated `TOOLS.generated.md` (and guidance, if it changed);
- the outcome recorded in [`ROADMAP.md`](../ROADMAP.md). Keep unfavourable old
  evidence; refresh baselines only through review.

Paid model-usability claims require approved comparable runs. When those are
unavailable, say so and label the result inconclusive — never invent a
percentage gain from local diagnostics.
