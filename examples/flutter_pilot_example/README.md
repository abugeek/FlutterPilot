# FlutterPilot example

A small todo app wired for FlutterPilot, and a walkthrough of what an agent
does with it. The todos come from [JSONPlaceholder](https://jsonplaceholder.typicode.com)
(reads are real; writes are echoed back and not stored, so the app keeps
its own list).

| Screen | Route | What it has |
|---|---|---|
| Todos | `/` | list (Dio + Riverpod), filter chips, a checkbox per row, pull to refresh, an error screen with Retry |
| New todo | `/add` | a form with validation; Save posts it |
| Todo | `/todo/:id` | details, mark as done/open |
| Settings | `/settings` | dark mode, kept in shared_preferences |

The wiring is all in [`lib/main.dart`](lib/main.dart): `FlutterPilot.initialize()`,
`DioPilotInterceptor`, `RiverpodPilotObserver`, `GoRouterPilotInspector.register`
and `SharedPrefsPilotInspector.register`. Riverpod 3 retries a failed
provider forever by default, so the `ProviderScope` turns that off and the
error screen shows instead.

## Run it

```bash
flutter run -d macos --vmservice-out-file=.dart_tool/flutterpilot_vm_uri
```

Any device works. Then connect an agent: `flutterpilot mcp install` in this
folder writes the MCP config, or drive the tools from a shell with the bridge:

```bash
cd ../../packages/flutterpilot_server
dart run tool/fp_bridge.dart -p ../../examples/flutter_pilot_example
```

```bash
curl -s localhost:8765 -d '{"name":"get_app_summary","arguments":{}}'
```

## Walkthrough: the server fails

Each step is one tool call, and each response already says what changed.

1. **Look.** `get_app_summary` gives the route, the tappable elements
   (`delectus aut autem [todo_1]`, `Done: delectus aut autem`, `Add todo
   [add_todo]` …) and any errors.
2. **Check accessibility.** `audit_screen_health` lists controls a screen
   reader can't name and where its reading order jumps. The checkboxes are
   named through `semanticLabel`, so it finds none; the order jumps from the
   last row back up to the floating button, as with any Scaffold FAB.
3. **Break the server.** `mock_http_response(urlPattern: "/todos",
   statusCode: 500, body: '{"error":"server_down"}')`. The app's Dio now
   fails the way it would against a real 500.
4. **Reload.** `swipe_widget(key: "todo_1", direction: "down")` →
   "Pulled to refresh", and the diff shows `Text["Couldn't load todos (HTTP 500)"]`
   and a Retry button.
5. **Assert it.** `assert_widget(text: "Couldn't load todos (HTTP 500)")` →
   passed. `get_network_logs` shows the request answered `500 [MOCKED]`.
6. **Recover.** `mock_http_response(clear: true)`, then
   `tap_widget(key: "Retry", waitFor: "todo_1")` → the list is back.

If step 4 had shown a crash instead, `get_errors(report: true)` names the
exception and the line in `lib/` that threw it; fix it and `hot_reload`,
then repeat steps 3–5. Mocks don't survive a hot restart; `scenario(save:)`
keeps them (see the root README).

## Walkthrough: a form

1. `tap_widget(key: "add_todo")` → route `/add`.
2. `tap_widget(key: "save_button")` with the field empty → `+ Text["Enter a title"]`.
3. `fill_form(fields: {"title_field": "Write the demo"}, submitWith: "save_button")`
   → the error goes; the POST takes a moment, so
   `wait_for(route: "/")`, then `assert_widget(text: "Write the demo")`.
4. `toggle_checkbox(key: "Done: Write the demo")` → the checkbox changes.
5. `navigate_to(route: "/settings")`, `toggle_checkbox(key: "Dark mode")`,
   `get_shared_preferences` → `{"dark_mode": true}`.

## Tests

`flutter test` runs [`test/app_test.dart`](test/app_test.dart) against a fake
API: filtering, adding (with validation), the error screen and Retry, and
dark mode being saved.
