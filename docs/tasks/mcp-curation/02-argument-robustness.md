# 02 · Argument robustness: coerce what clients send, fuzz every tool

**Branch:** `fix/arg-coercion` · **Depends on:** nothing · **Blocks:** 06

## Problem

Tools cast arguments directly, for example:

- `lib/src/tools/ui_automation_tools.dart:1079`:
  `for (final s in (p['steps'] as List?) ?? const [])` (execute_action_chain)
- `lib/src/tools/app_inspection_tools.dart:321`: same for another `steps`
- `lib/src/tools/app_inspection_tools.dart:554`:
  `(params['limit'] as int?) ?? 100` (get_debug_logs)
- plus `as num?`, `as Map`, `as List?` elsewhere
  (`grep -rnE "\] as (int|bool|num|double|List|Map)" lib`).

MCP clients and models regularly send:

| Sent | Schema says | Today |
|---|---|---|
| `"steps": "[{\"tool\":...}]"` | array | `TypeError` |
| `"limit": "100"` | integer | `TypeError` |
| `"enabled": "true"` | boolean | `TypeError` or silently wrong |
| `"count": 3.0` | integer | `TypeError` on `as int` |
| `"fields": "{\"Email\":\"a@b.c\"}"` | object | `TypeError` |

The `TypeError` is caught in `_registerTool()` (`lib/flutterpilot_server.dart`)
and returned as `"<tool> failed: type 'String' is not a subtype of type
'List<dynamic>?' in type cast. If the app was busy or reloading, retry; call
get_app_summary to check its state."` The advice is wrong: the agent retries
the same call, or goes to check app state.

This is test cases 1–4 of the `mcp-inspector-tester` skill (stringified JSON,
primitive coercion, missing required fields, extra fields). Extra fields are
already refused by `_tool()` (`unknownToolArguments`); keep that.

## Goal

1. One place, before any tool callback runs, that brings arguments to the
   schema's types when the intent is unambiguous, and otherwise refuses with
   a message naming the argument, the expected type and an example.
2. A test that calls **every registered tool** with malformed arguments and
   asserts a clean, actionable error (never a raw cast error, never a crash,
   never "retry").

## Design

### A. `coerceArguments` in a new file `lib/src/arg_coercion.dart`

```dart
/// What the schema expects of each argument, read once per tool from its
/// inputSchema.
sealed class ArgType { ... }  // string, integer, number, boolean, array(item), object, enum(values)

/// [args] with each value brought to its schema type where that is
/// unambiguous, or the first argument that can't be, as a message.
({Map<String, dynamic> args, String? problem}) coerceArguments(
  Map<String, dynamic> args,
  Map<String, ArgType> schema,
);
```

Rules (apply to top-level properties; for arrays of objects, also to each
element when the item schema is known, e.g. `steps[].arguments`, one level
only):

| Expected | Accept and convert | Refuse |
|---|---|---|
| integer | `"12"` → 12, `12.0` → 12 | `"12.5"`, `12.5`, `"abc"` |
| number | `"1.5"` → 1.5, int → double where needed | non-numeric strings |
| boolean | `"true"`/`"false"` (any case) → bool | `"yes"`, `1`, `0` (ambiguous: refuse) |
| array | a string whose trimmed text starts with `[` and parses as a JSON list | any other string; a lone object (don't wrap it) |
| object | a string starting with `{` that parses as a JSON map | other strings |
| string | numbers and bools → their `toString()` (keys like `todo_3` are sometimes sent as numbers) | arrays/objects |
| enum | case-insensitive match → the canonical value | anything else: list the allowed values |

`null` for an optional argument = absent (remove the key). `null` for a
required one = missing.

Missing required arguments: refuse before the callback with
`"<tool> needs <arg> (<type>), e.g. <example>; nothing was done."`. Today many
tools check this themselves with different wording; leave their own checks in
place (they may have tool-specific advice), the central check runs first only
for `required` in the schema. Check that no tool lists something as
`required` that it actually treats as optional (e.g. `key` OR `x`/`y`); if a
schema marks it required but the tool accepts alternatives, fix the schema,
not the check.

Error message shape (one sentence, then the fix):

```
execute_action_chain: "steps" must be an array of {tool, arguments}, got a string that is not JSON; nothing was done. Example: [{"tool": "tap_widget", "arguments": {"key": "Save"}}]
```

Examples per argument: take them from the property's `description` when it
contains `e.g.`; otherwise generate from the type (`"limit": 20`). Keep it
short.

### B. Wire it into `_tool()`

In `lib/flutterpilot_server.dart`, `_tool()` already builds `properties` from
`inputSchema` and wraps the callback in `checked`. Extend that:

1. Build the `Map<String, ArgType>` from `inputSchema` once at registration
   (not per call).
2. In `checked`: unknown-argument check (existing) → `coerceArguments` →
   problem? return `isError` → else `callback(withFormerNames(coerced), extra)`.

Order matters with `normalizeToolParams` / `withFormerNames`
(`param_aliases.dart`): aliases are resolved where they are resolved today;
make sure a coerced value is what the aliases copy (write a test for
`target: 3` → `key: "3"`).

Because `profile_action`, `run_on_devices`, `execute_action_chain` and the
leak `cycle` call other tools through `_toolCallbacks[name]` (the `checked`
wrapper), nested steps get coerced too. Verify this by test, don't assume.

### C. Fix the misleading catch-all

In `_registerTool()`'s `catch (e)`: when `e` is a `TypeError` (or
`CastError`/`FormatException`, check what Dart throws for `as`), the message
must not say "retry". Say the arguments did not match the tool's schema, name
the tool, and point at `tools/list`. With part A in place this should almost
never trigger; it is the safety net. Keep the existing message for other
exceptions.

### D. Fuzz test: `test/tool_argument_fuzz_test.dart`

Construct the server as `tool_registration_test` does
(`FlutterPilotServer(vmServiceUri: 'ws://localhost:8888')`, no app). You need
a way to call a tool's checked callback from the test: add a
`@visibleForTesting Future<CallToolResult> callToolForTest(String name,
Map<String, dynamic> args)` on the server that looks up `_toolCallbacks`.
Name and shape are your choice; keep it out of the MCP surface.

For every registered tool (iterate `registeredToolNames`, including native
and plugin tools: use the list-all mode `generate_tools_doc.dart` uses,
`FLUTTERPILOT_LIST_ALL_TOOLS`, or call callbacks directly), generate cases
from its schema:

1. `{}`: if the schema has required args → error naming one of them.
2. Each required arg missing in turn.
3. Each property with the wrong type: string for int/bool/array/object,
   number for string, object for array.
4. Each array/object property as a JSON **string** of a valid value → must
   be accepted (result is not the schema error; it may fail later because no
   app is connected, which is fine).
5. Each integer property as a numeric string → accepted.
6. An unknown extra argument → existing refusal.

Assertions for every case:

- The call completes (wrap in a 10 s timeout; no app is connected, so tools
  that wait for the app must fail fast. If one hangs, that is a bug to fix or
  a case to report, not to skip silently).
- No exception escapes.
- The result text never contains `is not a subtype of`, `type '`,
  `NoSuchMethodError`, `Null check operator`, `retry`.
- For cases 1–3, 6: `isError == true` and the text names the argument.
- For cases 4–5: the text does **not** contain the schema-error wording.

The test must be fast (whole file under ~30 s). If a tool needs a live app to
even reach argument handling, the central check in `checked` still runs first,
so this works without an app.

### E. Protocol check with the official Inspector (manual, once)

Run the server under the MCP Inspector CLI mode and capture the results in the
PR (verify flags with `npx @modelcontextprotocol/inspector --help`):

```bash
npx @modelcontextprotocol/inspector --cli dart run packages/flutterpilot_server/bin/flutterpilot_server.dart --method tools/list
```

Check: every tool has `inputSchema.type == "object"`, `required` only lists
existing properties, every property has a `type` and (except self-evident
ones like `clear`) a description, enum-like string params list `enum`. Fix
schema gaps you find in the same PR. List enum candidates you found but did
not convert (free strings that take a fixed set: `condition`, `gesture`,
`theme`, `level`, `action`…). Converting a string to an `enum` adds bytes to
the list; do it only where models are seen sending wrong values, and note the
byte change.

Also run the skill's headless tester once if Python is available, and paste
its report:

```bash
python C:/Users/abdul/.gemini/config/skills/mcp-inspector-tester/scripts/headless_tester.py -- dart run packages/flutterpilot_server/bin/flutterpilot_server.dart
```

Its findings are input, not requirements. Note what you fixed and what you
judged not applicable.

## Don't

- Don't coerce ambiguous values (`1` to bool, a bare object into a one-item
  array, `"yes"`). Refusing with an example is better than guessing.
- Don't change argument names or remove aliases.
- Don't touch tool behaviour after the arguments are valid.
- Don't make the description list longer to explain types; the schema says
  it.

## Tests summary

- `test/arg_coercion_test.dart`: table-driven tests of every rule above,
  including nested `steps[].arguments`, null handling, enum case-folding.
- `test/tool_argument_fuzz_test.dart`: as in D.
- Existing `param_aliases_test.dart` still passes; add the alias-after-coercion
  case.
- Show one fuzz case failing on the base commit (e.g. stringified `steps` on
  `execute_action_chain`).

Manual, on `../fp_lab_shop` running, via `fp_bridge.dart` (use a real key or
text from its first screen; the one below is a placeholder):

```bash
curl -s localhost:8765 -d '{"name":"execute_action_chain","arguments":{"steps":"[{\"tool\":\"tap_widget\",\"arguments\":{\"key\":\"<a product card key>\"}}]"}}'
```

```bash
curl -s localhost:8765 -d '{"name":"get_debug_logs","arguments":{"limit":"5"}}'
```

```bash
curl -s localhost:8765 -d '{"name":"get_debug_logs","arguments":{"limit":"five"}}'
```

The first two work as if typed correctly; the third is refused with an
example. Paste all three responses.

## Done when

- [ ] Coercion + required check run for every tool before its callback.
- [ ] Catch-all no longer says "retry" for argument type errors.
- [ ] Fuzz test covers every registered tool and passes; one case shown
      failing on base.
- [ ] Inspector `tools/list` audit pasted; schema gaps fixed or listed.
- [ ] e2e passes (README Definition of done, item 3).
- [ ] ROADMAP gets a line under §4 (token efficiency/robustness).
