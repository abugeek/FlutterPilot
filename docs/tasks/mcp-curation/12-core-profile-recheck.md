# 12 · Re-check the core tool profile against its purpose

**Branch:** `fix/core-profile` · **Base:** `integration/mcp-curation` until it
merges, then `main` · **Depends on:** 09

## Why

Task 08 asked for a core set of at most 20 tools, chosen with eval data. The
PR (#121) shipped 29, picked from the `expected_tools` listed in
`tasks.yaml`, not from eval runs (no key). Its reasoning was "29 + the Dart
MCP server's ~5 code tools still fits under Cursor's ~40". Neither number was
measured. The profile exists for clients with a tool limit, so the count is
the whole point.

## What to do

1. **Measure what sits next to FlutterPilot.** Start the Dart MCP server the
   way `flutterpilot mcp install` configures it (`dart mcp-server --disable
   flutter,dart_tooling_daemon`; read the exact args from `mcp_command.dart`)
   and count its `tools/list` (MCP Inspector CLI or a few lines of Dart).
   Paste the count and the names.
2. **Measure what the core profile shows a real app:** `fp_lab_shop` and
   `fp_lab_notes` with `--tools core` (task 09's field check has this). Note
   that plugin gating already drops some core tools per app.
3. **Find the current documented tool limit** for Cursor (and any other
   client in `McpClient` with one) from its own documentation, with the link
   and the date you checked. If you can't find a documented number, say so;
   don't use "~40" from memory.
4. **Decide the set:** core count + Dart MCP count must fit under the limit
   with room for one more small server (5 tools). If 29 fits, keep it and say
   why with the numbers. If not, cut the tools that are least needed in a
   limited client: start with the ones only a single eval task uses and that
   have an alternative (`get_memory_details`, `profile_action`,
   `get_secure_storage`, `exec_sql_query`, `simulate_network`), and list each
   cut with its reason. Decide on `gesture_widget` (now that it exists) the
   same way.
5. If the maintainer has approved eval runs by then: run task 01's suite with
   `--server-args "--tools core"` and `--compare` against the `all` run on
   the same commit. More than 2 of 14 tasks failing means the set is wrong
   (task 08's rule); adjust and re-run. Without a key, write "evals not run
   (no key)".

Update `coreTools`, its budget in `tool_registration_test.dart`,
`tool_profiles_test.dart`, the Cursor hint text in `mcp install` (it states a
number), and README/CLAUDE.md lines that state the count.

## Done when

- [ ] Dart MCP server tool count, Cursor's documented limit (with source),
      and per-app core counts in the PR.
- [ ] Core set justified by those numbers; changes (if any) made and tested.
- [ ] README Definition of done items 1–5, 7.
