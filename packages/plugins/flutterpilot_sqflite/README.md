# flutterpilot_sqflite

[FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin for apps using
**sqflite**: lets an AI agent (Claude Code, Cursor, VS Code…) see and drive
sqflite state in the running app through the FlutterPilot MCP server.

## Install

In your app folder, `flutterpilot init` detects sqflite and adds this plugin
(with `flutterpilot_sdk`). By hand:

```bash
flutter pub add flutterpilot_sdk flutterpilot_sqflite
```

## Wire it

The plugin does nothing until the app registers it, once, at startup:

```dart
import 'package:flutterpilot_sqflite/flutterpilot_sqflite.dart';

SqflitePilotInspector.registerDatabase('main', db);
```

`flutterpilot doctor` checks the wiring — and, while the app runs, that it
registered.

## Tools it adds

Listed by the server only once the app has registered the plugin:

- **`exec_sql_query`** — run SQL against the registered database (reads by default; writes need --allow-destructive)

The full tool reference is
[TOOLS.generated.md](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md).
FlutterPilot works in debug builds; `FlutterPilot.initialize()` does nothing
in release.
