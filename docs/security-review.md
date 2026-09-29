# Security review (ROADMAP §8), 2026-09-29

What FlutterPilot hands an agent, and what it lets one do, reviewed against
the code and tested against a running app. Every fix has a unit test, and the
redaction sweep runs in `tool/e2e_test.dart`: secrets are planted in the
fixture app, and every read tool's output must not contain them.

## Threat model

- **The agent sees tool results.** Anything in them may end up in a
  transcript, a log or a model provider's systems. Credentials the app holds
  must not be in them.
- **Files FlutterPilot writes may be committed.** That covers
  `flutterpilot/scenarios/*.json`, `flutterpilot/reports/*` and
  `integration_test/*_test.dart`.
- **Local attackers:** other users of the machine can read process lists.
  Web pages in the developer's browser can send requests to `localhost`.
- **Out of scope:**
  - Screenshots show whatever the screen shows.
  - An agent that is told to read a secret key directly (for example
    `get_secure_storage(key:)` on a non-sensitive name) gets it.
  - Release builds have no VM service.

## Findings

| # | Area | Finding | Status |
|---|---|---|---|
| S1 | Redaction: password fields | `get_widget_properties` returned an obscured field's text (`"text":"s3cret-pin"`). The widget tree copied `EditableText` text raw too, though compact trees happened to leave it out. | **Fixed**: both show `•` per character |
| S2 | Redaction: logs | Only `Bearer <token>` was masked. `api_key=…`, `password: …`, JWTs and `"token": "…"` printed by the app reached `get_debug_logs`, the summary's recent logs and error messages. | **Fixed**: one redactor (`Redaction.text`, the same in the SDK and the server). It masks sensitive `name=value` / `name: value` pairs, auth schemes and JWTs. Applied to console capture, the server's stdout log buffer and captured errors |
| S3 | Redaction: URLs | Query-string secrets (`?api_key=…`) showed in `get_network_logs` (Dio), `get_http_profile` (list and detail) and `verify_feature` reports. | **Fixed**: URLs go through the same redactor. Headers and JSON bodies were already masked; text bodies now are too (Dio) |
| S4 | Redaction: state | `get_state` printed every provider's value, including ones named like credentials (`authTokenProvider`). `scenario(save)` would have written them into a checked-in file. | **Fixed**: values of credential-named states are hidden, and other values have tokens masked. Scenarios leave credential-named states out and say so |
| S5 | Read-only SQL | `exec_sql_query` checked only the statement's prefix and blocked a few PRAGMAs by name. `WITH x AS (SELECT 1) DELETE FROM users` passed (sqflite's `rawQuery` runs any statement), as did `PRAGMA main.journal_mode = DELETE`, `PRAGMA user_version = 5` and `PRAGMA optimize`. | **Fixed**: one check (server, sqflite, drift). No writing keyword outside string literals, one statement only, and only listed read-only PRAGMAs without `=` |
| S6 | Shell bridge | `tool/fp_bridge.dart` bound to loopback but answered any POST. A web page can send a `text/plain` POST to `localhost:8765` without a CORS preflight, and could drive the app, including destructive tools when the bridge runs with `--allow-destructive`. | **Fixed**: requests with `Origin` or `Sec-Fetch-Mode` (browsers) get 403 |
| S7 | Test generation | Obscured text was passed as `--dart-define=FP_SECRET_1=…`, which any local user can read in the process list while the test builds and runs. | **Fixed**: a JSON file in a new temp folder (0700, the file 0600), passed with `--dart-define-from-file`, deleted afterwards. The value is still compiled into the test build, as any dart-define is |
| S8 | Remote VM connections | `connect_app`, `register_device`, discovery and the reconnect path all go through `_isAllowedConnectionUri`: loopback only unless `--allow-remote`, a VM token required for remote URIs, and optionally `--remote-token`. | **OK**. Remote VM service traffic is unencrypted ws://; use it on trusted networks only (already in the flag's help) |
| S9 | Destructive operations | Writing preferences, secure storage and Supabase sign-out need `--allow-destructive`, as does loading a scenario that has preferences. SQL is read-only (S5). `set_state` and mocks change memory only. | **OK**. `call_custom_tool` runs whatever the app registered: the app's author decides |
| S10 | Secure storage / preferences | Values redacted by default. Sensitive keys stay redacted even with `showValues` and when read one by one. | **OK** |
| S11 | Files and processes | Scenario, test and report names are checked (`[a-z0-9_-]`, slugs), so there is no path traversal. Every `Process.run` passes arguments as a list, with no shell. The CLI's one `runInShell` passes a fixed `test`. | **OK** |

## Not covered

- **Redaction is by name and pattern.** A secret under an innocent name (`"x": "hunter2"`) or in free text without a `name=` still shows.
- **Screenshots and on-screen `Text`** show what the user sees.
- **Database rows (`exec_sql_query`), Hive boxes and Firestore/Supabase query results** are returned as stored: the agent asked for exactly that data.
- **Native crash reports** are read from the Mac's own `DiagnosticReports`; their frames and messages are not redacted.
