# flutterpilot_hive

[FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin for apps using
**hive / hive_ce**: lets an AI agent (Claude Code, Cursor, VS Code…) see and drive
Hive state in the running app through the FlutterPilot MCP server.

## Install

In your app folder, `flutterpilot init` detects hive and adds this plugin
(with `flutterpilot_sdk`). By hand:

```bash
flutter pub add flutterpilot_sdk flutterpilot_hive
```

## Wire it

The plugin does nothing until the app registers it, once, at startup:

```dart
import 'package:flutterpilot_hive/flutterpilot_hive.dart';

HivePilotInspector.registerBox(box);
```

`flutterpilot doctor` checks the wiring — and, while the app runs, that it
registered.

## Tools it adds

Listed by the server only once the app has registered the plugin:

- **`get_hive_contents`** — keys and values of the registered boxes

The full tool reference is
[TOOLS.generated.md](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md).
FlutterPilot works in debug builds; `FlutterPilot.initialize()` does nothing
in release.
