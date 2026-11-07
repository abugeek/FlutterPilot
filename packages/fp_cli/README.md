# FlutterPilot CLI (`fp_cli`)

Official Command-Line Interface for FlutterPilot — 1-command init, development runner, multi-client MCP installer, and environment diagnostics for AI-driven Flutter development.

## 📦 Installation

Install globally via pub.dev (provides both `fp` and `flutterpilot` executables):

```bash
dart pub global activate fp_cli
```

Or from local checkout during development:
```bash
dart pub global activate --source path /path/to/FlutterPilot/packages/fp_cli
```

---

## ⚡ Core Commands

> **Note:** Every command can be invoked with either `fp` or `flutterpilot`.

### 1. `fp init`
Auto-analyzes your Flutter project dependencies and installs FlutterPilot SDK and matching state/storage plugins:

```bash
fp init
# Or link to a local checkout during development:
fp init --local /path/to/FlutterPilot
```

**What it does:**
- Scans `pubspec.yaml` for popular dependencies (`riverpod`, `bloc`, `dio`, `drift`, `hive`, `shared_preferences`, `supabase_flutter`, `firebase_auth`/`cloud_firestore`, `go_router`, `connectivity_plus`, `flutter_secure_storage`, `sqflite`).
- Adds `fp_sdk: ^0.1.0` and matching plugins to `dev_dependencies`.
- Patches `lib/main.dart` with `WidgetsFlutterBinding.ensureInitialized();` and `FlutterPilot.initialize();`.
- Prints the exact one-line wiring needed for each detected plugin (e.g. `DioPilotInterceptor.register()`).
- Runs `flutter pub get`.

---

### 2. `fp mcp install`
Configures your AI coding assistants with the FlutterPilot MCP server:

```bash
# Auto-detects clients used in the workspace:
fp mcp install

# Target specific clients:
fp mcp install --client claude,cursor,vscode,codex,gemini,zed

# Use core (compact) tool profile for strict token budgets:
fp mcp install --tools core
```

Supported clients:
- **Claude Code** (`.mcp.json`)
- **Cursor** (`.cursor/mcp.json`)
- **VS Code** (`.vscode/mcp.json`)
- **Gemini CLI** (`.gemini/settings.json`)
- **Codex CLI / IDE** (`.codex/config.toml`)
- **Zed** (`.zed/settings.json`)
- **Antigravity**, **opencode**, **Junie**, **Kiro**, **Roo Code**, and more.

---

### 3. `fp dev` (alias: `fp run`)
Runs your Flutter app in debug mode and automatically hooks the FlutterPilot MCP server to the detected VM Service URI:

```bash
fp dev
# Or target a specific device:
fp dev -d macos
fp dev -d chrome
fp dev -d emulator-5554
```

---

### 4. `fp doctor`
Diagnoses your environment to ensure everything is set up for autonomous AI development:

```bash
fp doctor
```

**Checks performed:**
- Flutter SDK & Dart SDK installations.
- Running Flutter apps and VM Service availability.
- Installed plugins and SDK initialization status.
- Connected simulators, emulators, and physical devices.
- MCP client configurations and server health.

---

### 5. `fp smoke`
Performs an automated runtime smoke check on a running app:

```bash
fp smoke
```
Inspects routes, verifies responsive layout scales (1x and 2x), detects accessibility or rendering overflows, and summarizes screen health findings.

---

### 6. `fp audit`
Performs an accessibility and UI health audit across connected screens:

```bash
fp audit
```
Checks for contrast ratios (WCAG 2.1 AA), tap target sizes (min 48x48 dp), missing labels, and screen-reader traversal order.

---

### 7. `fp stats`
Displays telemetry and performance metrics from local MCP sessions (call counts, latency, most-used tools).

---

### 8. `fp migrate`
Migrates legacy `flutterpilot_*` imports, dependencies, and configuration files to the clean `fp_*` naming scheme:

```bash
# Dry run:
fp migrate --dry-run

# Apply migration:
fp migrate
```
