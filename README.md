# FlutterPilot

[![CI](https://github.com/abugeek/FlutterPilot/actions/workflows/ci.yml/badge.svg)](https://github.com/abugeek/FlutterPilot/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.0-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%5E3.11-0175C2?logo=dart)](https://dart.dev)

**FlutterPilot** is a production-ready MCP (Model Context Protocol) toolkit that gives AI agents complete runtime control over Flutter applications. Powered by the Dart VM service, it enables autonomous testing, self-healing crashes, and AI-native development workflows.

> **Why FlutterPilot?** Flutter's built-in support for AI-driven development is limited. FlutterPilot fills that gap with **83 tools** for screenshots, UI automation, state inspection, error recovery, debug console capture, and full DevTools-level deep inspection — all designed specifically for how AI agents work.

## 🚀 Quick Start (3 Steps)

### 1️⃣ Add SDK to Your Flutter App
```bash
flutter pub add --dev flutterpilot_sdk
```
Then in `main.dart`:
```dart
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  FlutterPilot.initialize();
  runApp(MyApp());
}
```

### 2️⃣ Run Your App
```bash
flutter run
```
From the output, copy the **VM Service URI** (looks like `http://127.0.0.1:XXXXX/...=`).

### 3️⃣ Start the MCP Server
```bash
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri <paste-vm-service-uri-here>
```

**That's it!** Your AI agent (Claude, Cursor, etc.) can now see and control your running app.

---

## 📋 What You Get

### 83 MCP Tools Across 6 Categories

#### 🎬 **Screenshots & Layout** (5 tools)
- `capture_screenshot` — PNG screenshot as MCP Image
- `get_widget_tree` — Full widget hierarchy with positions
- `get_widget_properties` — Read text, enabled state, value, bounds from any widget
- `compare_screenshot` — Visual regression testing baseline
- `save_screenshot_baseline` — Save screenshot for comparisons

#### 🖱️ **UI Automation** (15 tools)
- `tap_at(x, y)` — Tap at screen coordinates
- `tap_widget(key)` — Tap a widget by its key
- `double_tap_widget(key)` — Double-tap a widget
- `long_press_widget(key)` — Long-press a widget
- `enter_text(key, text)` — Type into a text field
- `clear_text_field(key)` — Clear a text field
- `scroll_into_view(key)` — Scroll until widget is visible
- `scroll_by(dx, dy)` — Scroll by pixel amount
- `press_back` — Pop current route (hardware back button)
- `set_slider_value(key, value)` — Set slider to numeric value
- `toggle_checkbox(key)` — Toggle checkbox/switch/radio
- `focus_widget(key)` — Request focus on a widget
- `unfocus_all` — Dismiss keyboard
- `set_text_scale_factor(scale)` — Accessibility text scaling
- `pump_frames(count)` — Wait for N animation frames

#### 🧭 **Navigation & Routing** (8 tools)
- `navigate_to(route)` — Push a named route
- `get_navigation_stack` — Current route stack
- `simulate_deep_link(url)` — Trigger deep link routing
- `set_locale(locale)` — Switch app language at runtime
- `set_theme(theme)` — Switch light/dark mode
- `set_device_rotation(rotation)` — Device orientation
- `wait_for_state(condition, timeout)` — Wait until condition is true
- `hot_reload` — Apply code changes

#### 🔍 **State & Inspection** (19 tools)
- `get_app_summary` — Current route, errors, widget count
- `get_errors` — Buffered runtime errors
- `diagnose_last_error` — Full error report with state & stack
- `get_navigation_stack` — Route history
- `get_perf_metrics` — FPS, memory, frame timing
- `get_widget_tree` — Full widget JSON tree
- `get_semantics_tree` — Accessibility tree (VoiceOver/TalkBack)
- `assert_widget_enabled(key)` — Assert widget is interactive
- `assert_widget_disabled(key)` — Assert widget is disabled
- `get_riverpod_states` — Active Riverpod providers
- `get_bloc_states` — Active Bloc/Cubit states
- `get_network_logs` — HTTP requests/responses (Dio)
- `query_drift_db(sql)` — SQL queries on your database
- `get_hive_contents` — All local storage data
- `get_shared_preferences` — SharedPreferences contents
- `set_shared_preference` — Write to SharedPreferences
- `clear_shared_preferences` — Clear SharedPreferences
- `get_build_config` — pubspec.yaml + build metadata
- `read_dart_file(path)` — Read source files

#### 🖥️ **Debug Console** (3 tools) ✨ *New*
AI agents can read your app's console output automatically — no copy-pasting from VS Code.
- `get_debug_logs` — Captured `print()`, `debugPrint()`, `developer.log()` with level/logger filters
- `clear_debug_logs` — Reset the log buffer before a test scenario
- `set_log_filter` — Clear both server + in-app log buffers

#### 🔬 **DevTools Deep Inspection** (12 tools) ✨ *New*
Same VM Service Protocol as Flutter DevTools — but queryable by AI agents.
- `get_memory_details` — Heap used/capacity/external per isolate
- `get_allocation_profile` — Top Dart classes by heap bytes (memory leak detection)
- `get_gc_stats` — GC heap pressure across isolates
- `get_http_profile` — All HTTP requests with URL/method/status/timing
- `clear_http_profile` — Reset network tracking baseline
- `get_render_tree` — Render object tree dump (layout debugging)
- `get_layer_tree` — GPU compositing layer tree
- `get_vm_info` — Dart VM version, PID, all isolates
- `toggle_repaint_rainbow` — Visual repaint layer highlighting
- `toggle_debug_paint` — Layout bounds, padding, hit areas overlay
- `toggle_slow_animations` — 5× slow-motion animation inspection
- `enable_widget_rebuild_tracking` — Per-widget rebuild counting

#### 🩹 **Self-Heal & Testing** (20+ tools)
- `get_latest_crash_report` — Auto-intercepted crash with context
- `start_recording` — Record user interactions
- `stop_and_generate_test` — Generate test code from recording
- `list_custom_tools` — App-specific tools registered
- `call_custom_tool` — Execute app-specific tool
- And 15+ more...

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│              AI Agent (Claude, Cursor)               │
└──────────────────────┬──────────────────────────────┘
                       │ MCP Protocol (JSON-RPC/stdio)
┌──────────────────────▼──────────────────────────────┐
│          flutterpilot_server (modular)               │
│  • 83 MCP tools with full schemas + param descriptions│
│  • Organized into 9 tool categories (part files)     │
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
- **`flutterpilot_dio`** — View all HTTP requests/responses
- **`flutterpilot_drift`** — Query databases via SQL
- **`flutterpilot_hive`** — Inspect Hive key-value storage
- **`flutterpilot_shared_preferences`** — Inspect/edit SharedPreferences

---

## 🛠️ Integration Guide

### For Existing Flutter Projects

#### Step 1: Add Dependencies
```bash
cd your-flutter-project
flutter pub add --dev flutterpilot_sdk
# Optional plugins:
flutter pub add --dev flutterpilot_riverpod    # if using Riverpod
flutter pub add --dev flutterpilot_bloc        # if using Bloc
flutter pub add --dev flutterpilot_dio         # if using Dio
flutter pub add --dev flutterpilot_shared_preferences  # if using SharedPreferences
```

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
