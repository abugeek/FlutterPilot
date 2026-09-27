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
# 1. Install CLI
dart pub global activate --source path ./packages/flutterpilot_cli

# 2. In your Flutter project root, add the SDK + matching plugins (git deps)
#    and FlutterPilot.initialize() to main.dart. It prints the one wiring line
#    each plugin needs (e.g. dio.interceptors.add(DioPilotInterceptor())).
flutterpilot init            # or: flutterpilot init --local /path/to/FlutterPilot

# 3. Run the app, then point your agent's MCP config at the server:
flutter run
```

> Packages are not on pub.dev yet — `init` uses git (or `--local` path) dependencies.

### Option B: Zero-Code Mode (No App Changes Required)
Connect FlutterPilot MCP Server to **any existing Flutter app** to inspect it:
widget tree, screenshots, errors with source lines, logs, hot reload/restart,
theme and debug-paint toggles, memory and HTTP profiles. Driving the app
(taps, text entry, navigation, assertions) needs the SDK (Option A); without
it those tools are not listed.
```bash
# Run any vanilla Flutter app:
flutter run

# Start the MCP server (auto-discovers your app on localhost):
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
- VS Code (`.vscode/mcp.json`) uses `"servers"` instead of `"mcpServers"` and `"type": "stdio"`.
- Claude Code: `claude mcp add flutterpilot -- /ABSOLUTE/PATH/.../build/flutterpilot_server -p /ABSOLUTE/PATH/your_flutter_app`
- Run the app with `flutter run --vmservice-out-file=.dart_tool/flutterpilot_vm_uri` (or `flutterpilot dev`) so the server finds it.
- Rebuild the executable after pulling server changes.

## 📋 What You Get

### MCP Tools

The full, always-current list with every parameter is
**[TOOLS.generated.md](TOOLS.generated.md)** (generated from the server's
registrations). Plugin tools appear only when that plugin is installed. The
ones you'll use most:

**Orientation** — `get_app_summary` (call first: route, tappable elements,
errors, logs, window visibility), `get_interactive_elements`,
`get_widget_tree`, `get_widget_properties`, `capture_screenshot`.

**Driving the UI** — `tap_widget`, `enter_text`, `press_key`,
`secondary_tap`, `long_press_widget`, `double_tap_widget`, `swipe_widget`,
`drag_widget`, `scroll_into_view`, `toggle_checkbox`, `set_slider_value`,
`clear_text_field`, `press_back`. Batch known sequences with
`execute_action_chain`, `fill_form_batch`, `tap_and_wait`,
`enter_text_and_submit`. Every action reports its own result — route change,
what appeared/disappeared, tappable elements now, new errors — so you rarely
need a follow-up read.

**Verifying** — `assert_widget_visible`, `assert_text_visible`,
`assert_widget_count`, `assert_widget_enabled` / `assert_widget_disabled`,
`wait_for_condition`, `save_screenshot_baseline` + `compare_screenshot`,
`audit_screen_health`.

**Navigation & environment** — `navigate_to`, `get_navigation_stack`,
`simulate_deep_link`, `set_locale`, `set_text_scale_factor`,
`set_device_rotation` (mobile only), `hot_reload`, `hot_restart`.

**Errors** — `get_errors`, `get_latest_crash_report` (exception, your source
line, culprit widget), `get_debug_logs`, `get_flight_log`.

**Network** — `mock_http_response` / `clear_http_mocks`, `simulate_network`,
`get_network_logs` (Dio plugin), `get_http_profile` (any `dart:io` client).

**Performance** — `profile_frame_budget`, `get_memory_details`,
`get_allocation_profile`.

**State & storage (plugins)** — Riverpod `get_riverpod_state` /
`set_riverpod_state`, Bloc `get_bloc_state` / `set_bloc_state`, go_router,
SharedPreferences, `exec_sql_query` (Drift or sqflite, read-only), Hive /
Hive CE `get_hive_contents`, Supabase (`get_supabase_auth`,
`query_supabase_table`, `get_supabase_realtime`), secure_storage and
connectivity. Field-tested on real apps: Riverpod, go_router, Dio, sqflite,
SharedPreferences, connectivity, Bloc, Drift, Hive CE, secure_storage and
Supabase. Firebase is not yet (see [ROADMAP.md](ROADMAP.md) §2).

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
- **`flutterpilot_firebase`** — Crashlytics, Analytics, Performance, FCM
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

// If using Firebase:
await Firebase.initializeApp();
FirebasePilotInspector.register(
  crashlytics: FirebaseCrashlytics.instance,
  analytics: FirebaseAnalytics.instance,
  performance: FirebasePerformance.instance,
  messaging: FirebaseMessaging.instance,
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
// Human flow: Start recording, manually tap through your app
// AI flow: AI calls start_recording → waits for you → calls stop_and_generate_test
// Output: Copy-pasteable testWidgets block with all your taps
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
// Instead of tap_at(250, 450) which breaks on different screen sizes:
await mcp.call('tap_widget', {'key': 'submitButton'});

// Or with assertions:
await mcp.call('assert_widget_enabled', {'key': 'submitButton'});
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
3. Calls `set_text_scale_factor(2.0)` to test large text
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

A small number of **mutating** plugin tools do make real API calls to external services via the SDK instances you passed in. These are clearly marked with `⚠ MAKES REAL NETWORK CALL` in the tool description:

| Tool | Side Effect |
|------|-------------|
| `supabase_sign_out` | Calls `client.auth.signOut()` — signs out the real session |
| `supabase_refresh_session` | Calls `client.auth.refreshSession()` — rotates tokens |
| `log_analytics_event` | Sends event to Firebase Analytics dashboard |
| `record_crashlytics_error` | Sends error to Firebase Crashlytics dashboard |
| `start_performance_trace` | Starts a Firebase Performance trace (network call when stopped) |

> **Recommendation:** Only use these tools in development/test environments against non-production Firebase projects and Supabase instances. All other FlutterPilot tools are read-only and safe to use in any environment.

### ⚠️ Destructive Storage Tools

`delete_secure_storage_key` without a `key` argument wipes **all** secure storage. It requires `confirm="DELETE_ALL"` to proceed:

```
# Safe — deletes one key
delete_secure_storage_key(key: "session_token")

# Requires explicit confirmation — deletes everything
delete_secure_storage_key(confirm: "DELETE_ALL")
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
