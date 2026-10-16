# Official MCP Inspector interoperability check (task 03)

An independent-client smoke test for the FlutterPilot MCP server. It runs the
**pinned** official
[`@modelcontextprotocol/inspector`](https://www.npmjs.com/package/@modelcontextprotocol/inspector)
CLI against `bin/fp_server.dart` over stdio and asserts the discovery, call and
refusal surface a real, separately maintained client actually sees.

It complements — it does not replace — the raw JSON-RPC suite in
`test/mcp_protocol_compliance_test.dart`. The Inspector is one process per probe,
so it cannot observe same-session notifications, resource subscriptions or
malformed framing; the raw suite keeps those. This check answers a different
question: *does a client we did not write still interoperate?*

Node is needed **only** for this development check. Nothing here is a dependency
of the published Dart package, and the production server never needs Node.

## Pinned identity

Recorded at execution time; any of these changing is a setup error, never a
server pass.

| | |
|---|---|
| Package | `@modelcontextprotocol/inspector` |
| Version | **2.11.0** (exact; `package.json` + `package-lock.json`) |
| Tarball integrity | `sha512-gqMw2x0NCotTdjLNv3PSm/IJSeXL7O8u0SpyZXtXGhSukJ2DMoAy8RR7xKngHTCETJcG5gyPdxhOn8zf/ofSRA==` |
| Node engine floor | `>=22.19.0` (from the release's own `engines.node`) |
| Protocol era requested | `legacy` (classic `initialize`) |
| Verified on | Node **v24.18.0**, Dart **3.13.4** (stable), Windows x64 |

The Node version, the Dart version and the server's git revision are captured in
the run report, so a failure names the exact combination that produced it.

## Install and run

```sh
# from packages/fp_server
cd tool/inspector && npm ci --no-audit --no-fund && cd ../..

dart run tool/inspector/inspector_cli.dart                 # human summary
dart run tool/inspector/inspector_cli.dart --json          # machine report
dart run tool/inspector/inspector_cli.dart --report out.json
dart run tool/inspector/inspector_cli.dart --node /path/to/node
```

Exit code is `0` when every probe passes, `1` otherwise (a setup error — missing
`bin/fp_server.dart`, or an uninstalled Inspector — also exits `1`).

`npm ci` installs exactly the locked tree (~118 packages). `node_modules/` is
git-ignored; only `package.json` and `package-lock.json` are committed.

### Configuration

The wrapper writes its own **read-only** `mcpServers` config into a temp
directory for each run and passes it with `--config` (the Inspector reads this
file but never writes it, so the bytes stay ours). This avoids CLI/server flag
collisions and Windows quoting bugs, and isolates the OAuth/secret store
(`MCP_STORAGE_DIR`, `MCP_INSPECTOR_OAUTH_STATE_PATH`) away from a developer's
real tokens.

`inspector.config.example.json` documents that config's shape. It is an example
only — the wrapper does not read it, and it deliberately sets `command` to
`dart` for readability. The generated config uses the **absolute** Dart
executable path (`Platform.resolvedExecutable`), not the `dart` `.bat`/shell
shim: the Inspector spawns the command directly without a shell, and a `.bat`
cannot run that way.

**Headless by construction.** The config's `cwd` is the server package itself
(`packages/fp_server`) and no `roots` are configured, so the server has no
`.dart_tool/flutterpilot_vm_uri` to read and any Dart-Tooling-Daemon app it can
see is filtered to that subtree — a Flutter app running elsewhere on the machine
is never picked up. That is what makes the no-app probes (the safe
`list_connected_devices` call and the disconnected `resources/read` in
particular) reproducible rather than dependent on the workstation's state.



## What it proves

Ten one-shot invocations, each with its own bounded deadline:

1. `initialize` — connect-only handshake; asserts the server identifies as
   FlutterPilot and negotiates a protocol version.
2. `tools/list` — the surface is non-empty **and** contains a representative
   entry (`list_connected_devices`), so "non-empty" cannot be satisfied by a
   stray object.
3. `resources/list`, `resources/templates/list`, `prompts/list` — each
   non-empty, with `resources/list` also carrying a representative URI
   (`flutterpilot://app/summary`).
4. `tools/list --strict` — the bare-`ArgAny` warnings must not become
   error-severity schema findings (exit `6`).
5. `tools/call list_connected_devices` — a safe read with no app attached still
   returns content and is not an error.
6. `resources/read` on `flutterpilot://app/summary` — a disconnected read still
   returns contents (the "no app connected" body), not a JSON-RPC error.
7. `prompts/get flutterpilot_guide` — the guide expands to messages.
8. `tools/call execute_action_chain` with `{}` — a well-formed-looking call the
   server **must** refuse: asserts exit `5` (`tool_error`), `isError: true` in
   the stdout envelope, and that the message names the missing `steps`.
9. A recovery probe after the refusal — proves a rejected call leaves the server
   usable.

On a non-zero exit the CLI writes a one-line `{"error":{"code":…}}` envelope to
stderr; the wrapper decodes the exit class (`success`, `usage`, `no_app`,
`auth_required`, `unreachable`, `tool_error`, `schema_unportable`) and the error
code (a refusal reports `tool_is_error`). The wrapper never trusts exit `0`
alone: stdout must be exactly one JSON object, and the run must not have timed
out or hit the output cap.

## Protocol evidence

The task spec's starting point notes the evaluation session requests
`2024-11-05`; the pinned Inspector's `legacy` era drives the classic
`initialize`, which FlutterPilot answers with its newest classic version:

```
protocol: requested legacy, negotiated 2025-11-25
```

Setting `"protocolEra": "legacy"` in the generated config (rather than letting
the Inspector default to a newer stateless profile) is what makes a
`connect-only` initialize meaningful here.

## Strict schema findings (recorded, non-fatal)

`tools/list --strict` reports:

```
0 errors, 3 warnings across 2 tools.
```

The three warnings are the bare-`ArgAny` schemas already documented in
`lib/src/arg_coercion.dart` (`set_state.value`,
`mock_platform_channel.result` / `.event`). They are warnings, not errors, so
they do not change the exit code; the check asserts only that no
error-severity finding appears.

## Known limits

- **One shot, not a session.** The CLI runs per invocation; same-session
  notifications (`notifications/resources/updated`), subscriptions and
  unsubscribe semantics are proven by the raw suite, not here.
- **Headless list-all is not live gating.** The config sets
  `FLUTTERPILOT_LIST_ALL_TOOLS`, so `tools/list` is the full registered surface.
  That does **not** prove which tools a live app dynamic list would hide or
  expose — see the connected-fixture note below.
- **No cross-field callback checks.** A tool's semantic validation that lives in
  its callback rather than its schema (for example `gesture_widget`'s
  "gesture: swipe needs direction") is applied at execution, so a call can pass
  the protocol layer and only then be refused. This is the task-02 documented
  limit, not an Inspector finding.
- **Setup vs. server failure.** An npm/network outage fails the job as a setup
  error; it is never reported as a server pass.

## Connected-fixture run (manual)

To check dynamic discovery against a real app, start the server with all tools
listed off and point it at a connected fixture, e.g. a running sample app, then
compare the `tools/list` output with and without `FLUTTERPILOT_LIST_ALL_TOOLS`:
the normal (dynamic) list must reflect the app's SDK / plugin / core / zero-code
gating, while the list-all run exposes the whole surface. This run is not part of
CI because it needs a live device and a disposable app; it is a manual
verification step, and its result must not be represented as the headless run.

## CI

The `official-mcp-inspector` job in `.github/workflows/unit.yml` installs the
pinned tool and runs this wrapper on Linux and Windows, uploading the sanitized
JSON report as an artifact when the job fails. The report contains tool labels,
exit codes and check booleans — no server payloads, no secrets.
