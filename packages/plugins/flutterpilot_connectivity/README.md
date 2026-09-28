# flutterpilot_connectivity

[FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin for apps using
**connectivity_plus**: lets an AI agent (Claude Code, Cursor, VS Code…) see and drive
Connectivity state in the running app through the FlutterPilot MCP server.

## Install

In your app folder, `flutterpilot init` detects connectivity_plus and adds this plugin
(with `flutterpilot_sdk`). By hand:

```bash
flutter pub add flutterpilot_sdk flutterpilot_connectivity
```

## Wire it

The plugin does nothing until the app registers it, once, at startup:

```dart
import 'package:flutterpilot_connectivity/flutterpilot_connectivity.dart';

ConnectivityPilotInspector.register();
```

`flutterpilot doctor` checks the wiring — and, while the app runs, that it
registered.

## Tools it adds

Listed by the server only once the app has registered the plugin:

- **`get_connectivity`** — current network status and recent changes, as the app sees them

The full tool reference is
[TOOLS.generated.md](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md).
FlutterPilot works in debug builds; `FlutterPilot.initialize()` does nothing
in release.
