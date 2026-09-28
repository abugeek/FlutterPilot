# flutterpilot_shared_preferences

[FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin for apps using
**shared_preferences**: lets an AI agent (Claude Code, Cursor, VS Code…) see and drive
SharedPreferences state in the running app through the FlutterPilot MCP server.

## Install

In your app folder, `flutterpilot init` detects shared_preferences and adds this plugin
(with `flutterpilot_sdk`). By hand:

```bash
flutter pub add flutterpilot_sdk flutterpilot_shared_preferences
```

## Wire it

The plugin does nothing until the app registers it, once, at startup:

```dart
import 'package:flutterpilot_shared_preferences/flutterpilot_shared_preferences.dart';

SharedPrefsPilotInspector.register(await SharedPreferences.getInstance());
```

`flutterpilot doctor` checks the wiring — and, while the app runs, that it
registered.

## Tools it adds

Listed by the server only once the app has registered the plugin:

- **`get_shared_preferences`** — all stored keys and values
- **`set_shared_preference`** — write or remove a key (needs --allow-destructive)

The full tool reference is
[TOOLS.generated.md](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md).
FlutterPilot works in debug builds; `FlutterPilot.initialize()` does nothing
in release.
