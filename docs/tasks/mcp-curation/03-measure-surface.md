# 03 · Measure the surface: what each tool costs, what is never used

**Branch:** `feat/surface-report` · **Depends on:** nothing · **Blocks:** 04

## Goal

Task 04 decides which tools to merge. It needs two numbers per tool, per kind
of app:

1. **List cost:** bytes the tool adds to `tools/list` (what every session pays
   before calling anything).
2. **Use:** how often agents call it, how often it fails, how big its
   responses are, and which tools are *listed but never called*.

The call log already records `tool`, `ms`, `chars`, `err` per call
(`lib/src/call_log.dart`), and `flutterpilot stats` reports calls, failures,
averages and "what follows what" (`packages/flutterpilot_cli/lib/src/call_stats.dart`).
What's missing is the list cost per tool, the "listed but never called" view,
and aggregating several projects' logs.

## Deliverables

### A. `tool/tool_list_report.dart` (server package, dev script)

Prints, for each **app profile**, the tools listed and their bytes, sorted by
size, with a total, and writes the same as JSON with `--json`.

Profiles (reuse the sets the server uses, don't copy them):

| Profile | Listed tools |
|---|---|
| `all` | every tool (`--static-tools`) |
| `sdk_no_plugins` | `!pluginToolExtensions.containsKey(name) && !name.startsWith('native_')` (same as `tool_registration_test`) |
| `sdk_dio` | above + tools whose `pluginToolExtensions` needs are met by the Dio plugin's extensions |
| `sdk_lab_shop` | `../fp_lab_shop`'s plugins: dio, go_router, riverpod, sqflite, shared_preferences |
| `sdk_lab_notes` | `../fp_lab_notes`'s plugins: bloc, drift, hive, secure_storage, connectivity |
| `zero_code` | `zeroCodeTools` |
| `profile_build` | `sdk_lab_shop` minus `debugOnlyTools` |

Bytes: the same measure as `tool_registration_test.listBytes` (JSON of each
tool as listed, without `annotations`). Refactor `listBytes` into a function
in `lib/src/` that both the test and the script call, so the numbers can't
diverge. Also print an estimated token count (bytes / 4, labelled as an
estimate).

For the plugin profiles, find the extension names each plugin registers in
`packages/plugins/flutterpilot_<name>/lib` (`registerExtension` /
`ext.flutterpilot.<...>`), and put that mapping in the script with a comment
pointing at where it came from. If `plugin_tools.dart` already has it, use
that.

Example output:

```
sdk_lab_shop: 41 tools, 33 812 bytes (~8 450 tokens)
  tap_widget                 1 214
  set_app_settings           1 130
  ...
```

### B. Record what was listed, per session

Add one line per session to the call log when the listed set changes, so stats
can say what was available but unused:

```json
{"t":"...","s":1234,"listed":["get_app_summary","tap_widget", "..."]}
```

Write it from `updateToolVisibility()` when `changed` is true (after the
`sendToolListChanged`), and once at startup. Names only, as the log's
privacy note promises (no arguments, no app data). Update the doc comment at
the top of `call_log.dart` and `call_stats.dart` with the new line kind, and
make sure old readers skip it (today `callStatsReport` only takes lines with a
`tool` key: keep it that way and test it).

### C. `flutterpilot stats` additions

In `call_stats.dart` / `stats_command.dart`:

1. **Several logs:** `flutterpilot stats [paths...]` takes app folders or log
   files; default stays the current folder. Aggregate across them (sessions
   stay distinct per file: prefix the session id with the file index).
2. **Never called:** tools that were listed in a session (from B) and never
   called in any session in the window, sorted by list bytes when the server
   package is resolvable, else by name. Only shown when listed-lines exist.
3. **Response size:** add median and p90 `chars` per tool next to the average
   (averages hide the one 40 KB `get_widget_tree`).
4. `--json`: the same data as JSON, for task 04 to attach to its PR.

Keep the text report format stable for the existing sections; add the new
sections at the end.

### D. Collect real data (manual, part of this task)

Gather call logs from real sessions and attach the report to the PR:

- the lab apps (`../fp_lab_shop`, `../fp_lab_notes`): their
  `.dart_tool/flutterpilot_calls.jsonl` from task 01's eval runs and your own
  bridge sessions (the bridge goes through the server, so it logs too),
- `../pos_lab`: read its existing call log if there is one; don't modify the
  app,
- logs the maintainer has elsewhere (ask in your report; don't search the
  disk).

Calls you made by hand through the bridge are not agent behaviour: report
them separately from eval-run calls, or leave them out of the "never called"
view.

Note in the PR how many sessions and calls the report covers. Small samples
are fine; say how small.

## Tests

- `test/tool_list_report_test.dart` (or extend `tool_registration_test`):
  the shared `listBytes` gives the same totals the budget test checks; every
  profile is a subset of `all`; `zero_code` equals `zeroCodeTools`.
- `test/call_log_test.dart`: the listed-line is written on change only,
  holds names only, and survives `_trim()`.
- `packages/flutterpilot_cli/test/call_stats_test.dart`: old logs without
  listed-lines give the old report; never-called section; multi-log
  aggregation keeps sessions apart; median/p90; `--json` shape.

## Don't

- Don't log arguments, result text, routes, widget keys or anything from the
  app. Tool names only.
- Don't make `stats` slower than it is on a 2 MB log by more than a little;
  it reads the whole file today, that's fine.
- Don't change `CallLog.path` or the existing line fields.

## Done when

- [ ] `dart run packages/flutterpilot_server/tool/tool_list_report.dart`
      prints all six profiles; output pasted in the PR.
- [ ] Listed-lines written; `stats` shows never-called tools, median/p90,
      takes several logs, has `--json`.
- [ ] Report from real logs attached (D).
- [ ] Tests above pass; README Definition of done items 1–2, 4.
