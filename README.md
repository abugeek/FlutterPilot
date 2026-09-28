# FlutterPilot

[![CI](https://github.com/abugeek/FlutterPilot/actions/workflows/ci.yml/badge.svg)](https://github.com/abugeek/FlutterPilot/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.0-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%5E3.11-0175C2?logo=dart)](https://dart.dev)

**FlutterPilot** is an MCP (Model Context Protocol) toolkit that gives AI agents runtime control over Flutter applications. Powered by the Dart VM service, it enables autonomous testing, self-healing crashes, network chaos mocking, visual regression diffing, and AI-native development workflows.

> **Why FlutterPilot?** Standard Flutter has limited built-in support for AI-driven development. FlutterPilot bridges that gap with a broad, versioned tool set for screenshots with visual diffs, UI automation with live visual ripples, state inspection, error recovery, network mocking & latency simulation, full DevTools-level deep inspection, and multi-device fleet testing — across Riverpod, Bloc, Drift, Hive, Supabase, GoRouter, Firebase, Connectivity, and Secure Storage. Call `get_capabilities` to discover the exact runtime set.

## 🚀 Quick Start (Choose Your Workflow)

### Option A: The 1-Command CLI Workflow (Recommended)
```bash
# 1. Install CLI (from a checkout; `dart pub global activate flutterpilot_cli`
#    once it is on pub.dev)
dart pub global activate --source path ./packages/flutterpilot_cli

# 2. In your Flutter project root, add the SDK + matching plugins (git deps)
#    and FlutterPilot.initialize() to main.dart. It prints the one wiring line
#    each plugin needs (e.g. dio.interceptors.add(DioPilotInterceptor())).
flutterpilot init            # or: flutterpilot init --local /path/to/FlutterPilot

# 3. Add the FlutterPilot server to your agent's MCP config (.mcp.json for
#    Claude Code, .cursor/mcp.json, .vscode/mcp.json — the ones the project
#    uses; --client to choose). Compiles the server; other servers are kept.
flutterpilot mcp install

# 4. Run the app so the server finds it:
flutterpilot dev

# Something missing? Checks the setup and the running app, prints fixes:
flutterpilot doctor
```

> Packages are not on pub.dev yet — `init` uses git (or `--local` path) dependencies.

### Option B: Zero-Code Mode (No App Changes Required)
Connect FlutterPilot MCP Server to **any existing Flutter app** to inspect it:
widget tree, screenshots, errors with source lines, logs, hot reload/restart,
theme and debug-paint toggles, memory and HTTP profiles. Driving the app
(taps, text entry, navigation, assertions) needs the SDK (Option A); without
it those tools are not listed.
```bash
# Run any vanilla Flutter app, writing its VM service URI where FlutterPilot looks:
flutter run --vmservice-out-file=.dart_tool/flutterpilot_vm_uri

# Start the MCP server (finds the app in the current folder, the MCP client's
# workspace folders, or -p <app folder>):
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart
```

### Option C: Manual SDK Integration
```yaml
# pubspec.yaml
dependencies:
  flutterpilot_sdk:
    git:
      url: https://github.com/abugeek/FlutterPilot.git
      path: packages/flutterpilot_sdk
```
In `main.dart`:
```dart
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterPilot.initialize();
  runApp(const MyApp());
}
```

---

## 🔌 MCP Setup (any IDE)

`flutterpilot mcp install` (in the app folder) does all of this for Claude
Code, Cursor and VS Code and prints the `claude mcp add` line for user scope.
Run it again after pulling FlutterPilot changes — it recompiles the server.
By hand:

Build the server once (fast startup, no `dart` on the IDE's PATH needed):
```bash
cd packages/flutterpilot_server && dart compile exe bin/flutterpilot_server.dart -o build/flutterpilot_server
```

Then add it to your IDE's MCP config (Trae, Cursor, Windsurf, Claude Desktop use this `mcpServers` shape).
Use absolute paths; `-p` is your Flutter app's root:
```json
{
  "mcpServers": {
    "flutterpilot": {
      "command": "/ABSOLUTE/PATH/FlutterPilot/packages/flutterpilot_server/build/flutterpilot_server",
      "args": ["-p", "/ABSOLUTE/PATH/your_flutter_app"]
    }
  }
}
```
- Add `"--allow-destructive"` to `args` to allow state/storage writes.
- Without compiling: `"command": "/path/to/flutter/bin/dart", "args": ["run", "/ABSOLUTE/PATH/.../bin/flutterpilot_server.dart", "-p", "..."]` (slower start).
- VS Code (Copilot agent mode) reads `.vscode/mcp.json` in the app's folder,
  with `"servers"` and `"type": "stdio"`:
  ```json
  {
    "servers": {
      "flutterpilot": {
        "type": "stdio",
        "command": "/ABSOLUTE/PATH/FlutterPilot/packages/flutterpilot_server/build/flutterpilot_server",
        "args": ["-p", "${workspaceFolder}"]
      }
    }
  }
  ```
- Claude Code: `claude mcp add flutterpilot -- /ABSOLUTE/PATH/.../build/flutterpilot_server -p /ABSOLUTE/PATH/your_flutter_app`
- Run the app with `flutter run --vmservice-out-file=.dart_tool/flutterpilot_vm_uri` (or `flutterpilot dev`) so the server finds it.
- `-p` is optional when the client shares its workspace folders (MCP roots) and the app is in one of them, up to 3 levels deep (monorepos); with several apps running, the most recently launched wins. A plain `flutter run` can't be found — pass its URI to `connect_app`.
- Rebuild the executable after pulling server changes.

## 📋 What You Get

### MCP Tools

The full, always-current list with every parameter is
**[TOOLS.generated.md](TOOLS.generated.md)** (generated from the server's
registrations): 64 tools, of which an app sees only the ones that can work
for it — plugin tools once it registers that plugin (a Dio-only app sees 42).
Families are one tool with a parameter, not one tool per variant. The ones
you'll use most:

**Orientation** — `get_app_summary` (call first: route, tappable elements,
errors, logs, window visibility), `get_interactive_elements`,
`get_widget_tree` (`diff: true` for what changed), `get_widget_properties`,
`inspect_widget` (the file:line that draws a widget; `layout: true` for why
it overflows or is 0 wide), `capture_screenshot`.

**Driving the UI** — `tap_widget` (`gesture`: double / long / secondary;
`waitFor`: a widget to wait for), `enter_text` (`""` clears), `press_key`
(`"back"` for system back), `swipe_widget`, `drag_widget`,
`scroll_into_view`, `toggle_checkbox`, `set_slider_value`. Batch known
sequences with `execute_action_chain` or `fill_form`. Every action reports
its own result — route change, what appeared/disappeared, tappable elements
now, new errors — so you rarely need a follow-up read.

**Verifying** — `assert_widget` (text, key, enabled, type + count),
`wait_for` (widget, route, animations, state, frames), `compare_screenshot`
(`save: true` for the baseline), `audit_screen_health`.

**Navigation & environment** — `navigate_to` (deep links, go_router
push/replace), `get_navigation_stack`, `set_app_settings` (theme, locale,
text scale, orientation, debug overlays), `hot_reload` (`restart: true`).

**Errors** — `get_errors` (`report: true`: exception, your source line,
culprit widget, recent actions), `get_debug_logs`, `get_flight_log`.

**Network** — `mock_http_response` (`clear: true` to remove),
`simulate_network`, `get_network_logs` (Dio plugin), `get_http_profile`
(any `dart:io` client).

**Performance** — `profile_frame_budget`, `profile_action` (CPU
profile of one tap/scroll with file:line, and why its slow frames were slow), `get_memory_details`
(`classes: true` for the top classes).

**State & storage (plugins)** — Riverpod and Bloc `get_state` /
`set_state`, go_router (in the navigation tools),
SharedPreferences, `exec_sql_query` (Drift or sqflite, read-only), Hive /
Hive CE `get_hive_contents`, Supabase (`get_supabase_auth`,
`query_supabase_table`, `supabase_session`), Firebase
(`get_firebase_auth`, `query_firestore`), secure_storage and connectivity.
Field-tested on real apps: Riverpod, go_router, Dio, sqflite,
SharedPreferences, connectivity, Bloc, Drift, Hive CE, secure_storage,
Supabase and Firebase (Auth + Firestore, on the local emulators).

**Devices** — `connect_app`, `list_connected_devices`, `register_device`,
`switch_device`: one server drives several running apps (e.g. iOS simulator,
Android emulator, Chrome), one active device at a time.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│              AI Agent (Claude, Cursor)               │
└──────────────────────┬──────────────────────────────┘
                       │ MCP Protocol (JSON-RPC/stdio)
┌──────────────────────▼──────────────────────────────┐
│          flutterpilot_server (modular)               │
│  • Versioned MCP tools with full schemas + parameter descriptions│
│  • Organized into 9 tool categories (part files)      │
│  • Auto crash detection → AI notification            │
│  • VM Service bridge with auto-reconnect             │
└──────────────────────┬──────────────────────────────┘
                       │ VM Service Extensions
┌──────────────────────▼──────────────────────────────┐
│          flutterpilot_sdk (in-app, modular)           │
│  • 43+ service extensions across 5 modules           │
│  • Widget tree inspection via Element walking        │
│  • Screenshot capture (RenderRepaintBoundary)        │
│  • Error/nav/interaction tracking                    │
├─────────────┬──────────┬──────────┬────────┬────────┤
│ BlocPlugin │RiverpodP │DioPlugin │DriftPl│HivePlugin
│   (Bloc)   │(Riverpod)│(Network) │(DB)   │(Storage)
│            │          │          │       │SharedPref
├─────────────┼──────────┼──────────┼────────┼────────┤
│ Supabase   │GoRouter  │Connectiv │Firebase│SecureSt │
│  (Auth)    │ (Routes) │ (Network)│(Crash) │(Encrypt)│
└─────────────┴──────────┴──────────┴────────┴────────┘
```

---

## 📦 Core & Plugin Packages

### Core (Required)
- **`flutterpilot_sdk`** (v0.1.0) — Zero external dependencies. Just Flutter + `meta`.
- **`flutterpilot_server`** (v0.1.0) — MCP bridge to your app.

### Plugins (Optional — Add Only What You Need)
- **`flutterpilot_riverpod`** — Inspect/inject Riverpod providers
- **`flutterpilot_bloc`** — Inspect/inject Bloc/Cubit state
- **`flutterpilot_dio`** — View all HTTP requests/responses, mock endpoints
- **`flutterpilot_drift`** — Query SQLite databases via SQL
- **`flutterpilot_hive`** — Inspect Hive key-value storage
- **`flutterpilot_shared_preferences`** — Inspect/edit SharedPreferences
- **`flutterpilot_supabase`** — Auth state, session, realtime channels
- **`flutterpilot_gorouter`** — Route state, config, history, programmatic navigation
- **`flutterpilot_connectivity`** — Network status, history, simulated offline
- **`flutterpilot_firebase`** — Firebase Auth user and Firestore reads (as the app sees them)
- **`flutterpilot_secure_storage`** — Encrypted key-value inspection (auto-redacted)

---

## 🛠️ Integration Guide

### For Existing Flutter Projects

#### Step 1: Add Dependencies
```bash
cd your-flutter-project
flutterpilot init   # detects Riverpod/Bloc/Dio/Drift/sqflite/... and adds matching plugins
flutter pub get
```
Plugins do nothing until wired up — `init` prints the exact line for each one.
If the app has a macOS runner, `init` also adds the `network.client`
entitlement (sandboxed macOS apps can't make HTTP requests without it).
`flutterpilot doctor` checks the wiring (SDK initialized, each plugin used,
macOS network entitlement, MCP config) and, while the app runs, that the SDK
and every plugin registered — with the exact fix for anything missing.

#### Step 2: Initialize SDK
```dart
// main.dart
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  FlutterPilot.initialize();  // Before runApp!
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [NavigationTracker()],  // Track routes
      home: MyHome(),
    );
  }
}
```

#### Step 3: Add Plugin Observers (Optional)
```dart
// If using Riverpod:
ProviderScope(
  observers: [RiverpodPilotObserver()],
  child: MyApp(),
)

// If using Bloc:
MultiBlocProvider(
  providers: [
    BlocProvider(create: (_) => MyBloc()),
  ],
  child: MyApp(),
)
// Note: Bloc plugin auto-registers via VM extension

// If using Dio:
final dio = Dio();
dio.interceptors.add(DioPilotInterceptor());

// If using SharedPreferences:
final prefs = await SharedPreferences.getInstance();
SharedPrefsPilotInspector.register(prefs);

// If using Hive:
final myBox = await Hive.openBox('myData');
HivePilotInspector.registerBox(myBox);

// If using Supabase:
await Supabase.initialize(url: '...', anonKey: '...');
SupabasePilotInspector.register(Supabase.instance.client);

// If using GoRouter:
final router = GoRouter(routes: [...]);
GoRouterPilotInspector.register(router);

// If using connectivity_plus:
ConnectivityPilotInspector.register();

// If using Firebase Auth / Firestore:
await Firebase.initializeApp(...);
FirebasePilotInspector.register(
  auth: FirebaseAuth.instance,
  firestore: FirebaseFirestore.instance,
);

// If using flutter_secure_storage:
const storage = FlutterSecureStorage();
SecureStoragePilotInspector.register(storage);
```

#### Step 4: Run App & Server
```bash
# Terminal 1: Run the app
flutter run

# Terminal 2: Copy the VM Service URI from Terminal 1 output, then run server
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri http://127.0.0.1:12345/abcdefg=/
```

#### Step 5: Connect Your AI Agent
Use FlutterPilot in Claude Desktop, Cursor, or any MCP-compatible IDE:

**For Claude Desktop** (`~/.claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "flutterpilot": {
      "command": "dart",
      "args": [
        "run",
        "/path/to/FlutterPilot/packages/flutterpilot_server/bin/flutterpilot_server.dart",
        "--uri",
        "http://127.0.0.1:12345/abcdefg=/"
      ]
    }
  }
}
```

**That's it!** The AI can now:
- See your app (screenshots)
- Tap buttons, fill forms, navigate
- Read widget state, errors, network logs
- Suggest and apply fixes
- Write integration tests

---

## 🔥 Key Features in Depth

### 1. **Autonomous Testing**
```dart
// The agent drives the flow with tap_widget / enter_text / fill_form,
// checks each step with assert_widget, and writes the testWidgets block
// from the steps it took.
```

### 2. **Self-Healing Crashes**
```
Your app crashes while navigating.
↓ 
Server auto-captures: screenshot, widget tree, error, state, stack trace
↓
Server emits: "🚨 CRITICAL APP CRASH: SELF-HEAL REQUEST"
↓
AI sees notification, analyzes bug, suggests/implements fix
↓
Hot reload applied, app recovers
```

### 3. **Widget-Level Automation**
```dart
// Instead of tapping at (250, 450), which breaks on other screen sizes:
await mcp.call('tap_widget', {'key': 'submitButton'});

// Or with assertions:
await mcp.call('assert_widget', {'key': 'submitButton', 'enabled': true});
```

### 4. **State Injection**
```dart
// AI can directly set Riverpod/Bloc state at runtime:
await mcp.call('set_state', {
  'type': 'riverpod',
  'name': 'userProvider',
  'value': {'id': 1, 'name': 'Alice'}
});
```

### 5. **Full Semantics Tree Access**
```dart
// AI understands accessibility tree (labels, roles, bounds):
await mcp.call('get_semantics_tree');
// Returns VoiceOver/TalkBack structure for blind user testing
```

---

## 📖 Full Documentation

- **[SDK API Reference](packages/flutterpilot_sdk/README.md)** — Service extensions, custom tools, state injection
- **[Server & Tools Guide](packages/flutterpilot_server/README.md)** — Tool descriptions, MCP config, prerequisites
- **[Contributing Guide](CONTRIBUTING.md)** — Development setup, code style, architecture details
- **[Example App](examples/flutter_pilot_example)** — Full demo with Riverpod, Bloc, Dio, Hive
- **[Tool Reference](TOOLS.md)** — Detailed per-tool documentation with examples

---

## 🎓 Real-World Use Cases

### Use Case 1: AI-Powered Test Generation
1. Manually explore your app, clicking around
2. FlutterPilot records every tap, text entry, scroll
3. AI converts to `testWidgets` code
4. **Result:** Weeks of manual test writing → minutes

### Use Case 2: Autonomous Bug Fixing
1. App crashes in production
2. QA immediately captures crash + context via FlutterPilot
3. AI analyzes screenshot, error, state, and suggests fix
4. Hot reload applied, app recovers
5. **Result:** Faster debugging, self-healing apps

### Use Case 3: Cross-Device Testing
1. Run same app on iPhone + Android simulators simultaneously
2. Run one FlutterPilot server instance per device
3. AI tests both in parallel (form filling, animations, layout)
4. **Result:** Visual regression detected automatically

### Use Case 4: Accessibility Testing
1. Call `get_semantics_tree` to get VoiceOver/TalkBack structure
2. AI validates all labels, roles, bounds
3. Calls `set_app_settings(textScale: 2.0)` to test large text
4. **Result:** WCAG compliance verified programmatically

---

## ⚡ Performance

- **SDK overhead:** ~2% (lightweight service extensions only)
- **Screenshot:** ~500ms (native RenderRepaintBoundary)
- **Widget tree JSON:** ~100ms for 500-widget app
- **Tap simulation:** <50ms
- **Tool timeout:** 10-15 seconds (configurable)

---

## 🔐 Authentication & Credentials

**FlutterPilot requires zero accounts, zero logins, and zero credentials of its own.**

It is a development tool — the MCP server connects directly to your app's Dart VM (same machine, same debug session). No cloud service involved.

### Plugin Auth Model

Plugin packages wrap your already-initialized, already-authenticated SDK instances:

```dart
// Your app already initializes Supabase — FlutterPilot just wraps it:
await Supabase.initialize(url: '...', anonKey: '...');
SupabasePilotInspector.register(Supabase.instance.client); // no extra login
```

FlutterPilot never connects to Supabase, Firebase, or any other external service on its own.

### ⚠️ Tools That Make Real External Calls

One **mutating** plugin tool makes real API calls to an external service via the SDK instance you passed in, and only with `--allow-destructive`:

| Tool | Side Effect |
|------|-------------|
| `supabase_session(action: "sign_out")` | Calls `client.auth.signOut()` — signs out the real session |
| `supabase_session(action: "refresh")` | Calls `client.auth.refreshSession()` — rotates tokens |

> **Recommendation:** Only use these tools in development/test environments against non-production Supabase instances. All other FlutterPilot tools are read-only and safe to use in any environment.

### ⚠️ Destructive Storage Tools

`set_secure_storage_key(delete: true)` without a `key` wipes **all** secure storage. It requires `confirm="DELETE_ALL"` to proceed:

```
# Deletes one key
set_secure_storage_key(key: "session_token", delete: true)

# Requires explicit confirmation — deletes everything
set_secure_storage_key(delete: true, confirm: "DELETE_ALL")
```

---

## 🤝 Contributing

FlutterPilot is open source! We welcome:
- Bug reports
- Feature requests
- Tool contributions (email AI agents are always hungry for more context)
- Plugin contributions (Getx, Provider, Supabase, Firebase, etc.)
- Documentation improvements

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and guidelines.

---

## 📜 License

MIT — see [LICENSE](LICENSE). Free for personal and commercial use.

---

## 🙌 Credits

Built with ❤️ for Flutter developers who want to level up their AI-native development workflow.

**Questions?** Open an issue on [GitHub](https://github.com/abugeek/FlutterPilot).

**Want to extend?** See the [Contributing Guide](CONTRIBUTING.md) — adding a new tool takes ~30 minutes.
