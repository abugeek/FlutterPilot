# FlutterPilot CLI (`flutterpilot_cli`)

Official Command-Line Interface for FlutterPilot — 1-command init, unified development runner, multi-framework test generation, and environment diagnostics for AI-driven Flutter development.

## 📦 Installation

To install `flutterpilot` globally via Dart:

```bash
dart pub global activate --source path /path/to/FlutterPilot/packages/flutterpilot_cli
# Or from git:
# dart pub global activate --source git https://github.com/abugeek/FlutterPilot.git --git-path packages/flutterpilot_cli
```

---

## ⚡ Commands

### 1. `flutterpilot init`
Auto-analyzes your Flutter project dependencies and installs FlutterPilot SDK and matching state/storage plugins:

```bash
flutterpilot init
```

**What it does:**
- Scans `pubspec.yaml` for popular dependencies (`riverpod`, `bloc`, `dio`, `drift`, `hive`, `shared_preferences`, `supabase_flutter`, `firebase_core`, `go_router`, `connectivity_plus`, `flutter_secure_storage`, `sqflite`).
- Adds `flutterpilot_sdk: ^0.1.0` and matching plugins to `dev_dependencies`.
- Patches `lib/main.dart` with `WidgetsFlutterBinding.ensureInitialized();` and `FlutterPilot.initialize();`.
- Runs `flutter pub get`.

---

### 2. `flutterpilot dev` (or `flutterpilot run`)
Runs your Flutter app in debug mode and automatically hooks the FlutterPilot MCP server to the detected VM Service URI:

```bash
flutterpilot dev
# Or target a specific device:
flutterpilot dev -d macos
flutterpilot dev -d chrome
flutterpilot dev -d emulator-5554
```

---

### 3. `flutterpilot export-test`
Exports recorded interactive user journeys directly to production-ready test suites for Patrol, standard Flutter Integration Test, or Widget Tests:

```bash
# Export Patrol test (default)
flutterpilot export-test --framework=patrol --output=integration_test/checkout_test.dart

# Export standard Flutter Integration Test
flutterpilot export-test --framework=integration --output=integration_test/flow_test.dart

# Export Flutter Widget Test
flutterpilot export-test --framework=widget --output=test/flow_test.dart
```

---

### 4. `flutterpilot doctor`
Diagnoses your environment to ensure everything is set up for autonomous AI development:

```bash
flutterpilot doctor
```

**Checks performed:**
- Flutter SDK & Dart SDK installations.
- Connected simulators, emulators, and physical devices.
- Claude Desktop (`claude_desktop_config.json`) and Cursor (`.cursor/mcp.json`) MCP server configurations.
