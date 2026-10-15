# 08 · Core tool profile for clients with a tool limit

**Branch:** `feat/tools-core` · **Depends on:** 04 (so the core set is chosen
from the final names)

## Problem

Some clients cap or degrade with many tools across all servers (Cursor has
historically had a total limit around 40; others slow down or truncate). A
Flutter project often also runs the Dart MCP server and others. FlutterPilot
alone lists ~30–45 tools for a typical app.

## Goal

A server option `--tools core|all` (default `all`, so nothing changes for
existing users) and the same option on `flutterpilot mcp install`, writing it
into the config of the clients that need it.

## Design

### A. The core set

Defined in one place: `lib/src/tool_profiles.dart`,
`const coreTools = <String>{...}`. Choose from task 03's data and task 01's
evals: the tools the 14 eval tasks used, plus what an agent needs to recover
(`get_app_summary`, `get_errors`, `hot_reload`, `launch_app`). Target ≤ 20.
A starting point to check against the data, not to copy:

`launch_app`, `get_app_summary`, `capture_screenshot`, `get_widget_tree`,
`inspect_widget`, `tap_widget`, `enter_text`, `press_key`,
`scroll_into_view`, `fill_form`, `execute_action_chain`, `navigate_to`,
`wait_for`, `assert_widget`, `get_errors`, `get_debug_logs`, `hot_reload`,
`get_state`, `mock_http_response`, `audit_screen_health`.

The core set is **intersected** with what works for the app (the existing
`updateToolVisibility()` logic), never added to it: a zero-code app with
`--tools core` sees `coreTools ∩ zeroCodeTools`.

### B. Server

- `--tools` option in `lib/src/cli.dart`, `allowed: ['core', 'all']`.
- In `updateToolVisibility()`, a tool outside the profile is never enabled.
  `--static-tools` + `--tools core` lists exactly the core set.
- `get_app_summary(setup: true)` says which profile is active and that
  `--tools all` lists more. Don't add this to the normal summary (costs bytes
  every call).
- A step runner (`execute_action_chain`, `run_on_devices`, …) may still run
  non-core tools as steps? Decide: **no**, refuse with "not listed in the
  core profile; start the server with --tools all". Hidden-but-callable tools
  are confusing.

### C. CLI

- `flutterpilot mcp install --tools core|all` writes `--tools core` into the
  server args for the selected clients. Default: `all` for every client.
  Print a one-line hint after installing for Cursor:
  `"Cursor limits tools across servers; flutterpilot mcp install --client
  cursor --tools core lists 20."` (adjust to the real number). Don't change
  Cursor's default without the maintainer's decision; ask in the PR.
- `flutterpilot doctor` reports the profile in each client config it reads.

### D. Docs

README "MCP Setup" section and `CLAUDE.md` CLI section: one line each. Not in
`serverInstructions`.

## Tests

- `test/tool_profiles_test.dart`: every name in `coreTools` is registered;
  `core` ∩ zero-code / plugin gating; `--static-tools --tools core` lists
  exactly core.
- Step runner refuses a non-core step under `core`.
- CLI test (`packages/flutterpilot_cli/test/`): `mcp install --tools core`
  writes the arg for each client format (JSON, TOML for Codex, Zed's
  `context_servers`); default writes no `--tools`.
- `tool_registration_test`: add a budget for the core profile's list bytes.

Evals: run task 01's suite with the server started with `--tools core` (the
runner needs a `--server-args` option if it doesn't have one; add it). Report
pass rate vs the `all` baseline. Some tasks are expected to fail under core
(they need a non-core tool); list which and why. A core profile where more
than 2 of 14 tasks fail is the wrong core set: adjust it.

## Done when

- [ ] `--tools core|all` on server and `mcp install`; doctor shows it.
- [ ] Core set justified in the PR with the data used.
- [ ] Tests pass; e2e passes with default (`all`); evals under `core`
      reported.
