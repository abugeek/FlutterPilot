# FlutterPilot

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

FlutterPilot is a modular MCP (Model Context Protocol) tool suite designed to give AI agents deep runtime introspection into your Flutter applications.

## Architecture

```
AI Agent (Claude, Cursor, etc.)
    │ MCP Protocol (JSON-RPC over stdio)
    ▼
flutterpilot_server ── 30+ tools: screenshot, tap, state, navigation, self-heal...
    │ VM Service Extensions
    ▼
flutterpilot_sdk (in-app) ── widget tree, errors, screenshots, UI automation
    │
    ├── flutterpilot_bloc       (optional)
    ├── flutterpilot_riverpod   (optional)
    ├── flutterpilot_dio        (optional)
    ├── flutterpilot_drift      (optional)
    └── flutterpilot_hive       (optional)
```

## Core Packages

- **`flutterpilot_sdk`**: The lightweight core. Handles screenshots, errors, navigation, UI interaction, and test recording. **Zero external dependencies.**
- **`flutterpilot_server`**: The MCP server that bridges AI agents to your app.

## Plugin Packages (Optional)

Install only what you need to keep your project lean:

- **`flutterpilot_riverpod`**: Inspect active Riverpod providers.
- **`flutterpilot_bloc`**: Inspect active Bloc/Cubit states.
- **`flutterpilot_dio`**: View Dio HTTP traffic.
- **`flutterpilot_drift`**: Query your Drift database via SQL.
- **`flutterpilot_hive`**: Dump Hive box contents.

---

## Getting Started

### 1. Add the Core SDK
In `pubspec.yaml`:
```yaml
dev_dependencies:
  flutterpilot_sdk: { path: ../tools/packages/flutterpilot_sdk }
```

In `main.dart`:
```dart
void main() {
  FlutterPilot.initialize();
  runApp(const MyApp());
}
```

### 2. Add Plugins (Optional)
Example for Riverpod:
1. Add `flutterpilot_riverpod` to `dev_dependencies`.
2. Add the observer:
```dart
ProviderScope(
  observers: [RiverpodPilotObserver()],
  child: MyApp(),
)
```

### 3. Run the Server
```bash
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart --uri <vm-service-uri>
```
*Use `--allow-destructive` if you want the AI to run non-SELECT SQL queries.*

---

## The "Steroid" Features

### 👁️ AI Vision
Agents like Claude and Gemini can "see" your app. Calling `capture_screenshot` returns a native MCP Image response, allowing the AI to debug layout and color issues directly from the pixels.

### 🎯 Active Control & Automation
FlutterPilot gives agents "hands". They can:
- **`tap_at(x,y)` / `tap_widget(key)`:** Tap specific elements.
- **`enter_text(key, text)`:** Fill out forms.
- **`navigate_to(route)`:** Move around your app.
- **`scroll_into_view(key)`:** Scroll lists autonomously.

### 📝 Autonomous Test Generation
You can have the AI write integration tests for you based on your actual taps.
1. Call `start_recording`.
2. Tap through your app manually.
3. Call `stop_and_generate_test`. 
The AI receives a structured log of exactly what you did and outputs a copy-pasteable `testWidgets` block.

### 📍 Source Mapping & Platform Control
FlutterPilot connects the running app directly to your source code:
- **`jump_to_source`:** The widget tree now includes exact file paths and line numbers (`creationLocation`) so the AI knows exactly where a widget is defined.
- **`set_theme`:** Force the app into `light` or `dark` mode.
- **`show_performance_overlay`:** Toggle the Flutter performance overlay to detect jank.

### 🩹 The Autonomous "Self-Heal" Loop
The server listens to the VM service. If your app throws an error while you're navigating, the server will instantly intercept the crash, gather all context (Screenshot, State, Stacktrace), and emit a `CRITICAL APP CRASH: SELF-HEAL REQUEST` to the terminal. The connected AI agent will see this, analyze the bug, and fix it proactively!

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, architecture details, and PR guidelines.

## License

MIT — see [LICENSE](LICENSE) for details.
