# flutterpilot_secure_storage

[FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin for apps using
**flutter_secure_storage**: lets an AI agent (Claude Code, Cursor, VS Code…) see and drive
Secure Storage state in the running app through the FlutterPilot MCP server.

## Install

In your app folder, `flutterpilot init` detects flutter_secure_storage and adds this plugin
(with `flutterpilot_sdk`). By hand:

```bash
flutter pub add flutterpilot_sdk flutterpilot_secure_storage
```

## Wire it

The plugin does nothing until the app registers it, once, at startup:

```dart
import 'package:flutterpilot_secure_storage/flutterpilot_secure_storage.dart';

SecureStoragePilotInspector.register(storage);
```

`flutterpilot doctor` checks the wiring — and, while the app runs, that it
registered.

## Tools it adds

Listed by the server only once the app has registered the plugin:

- **`get_secure_storage`** — stored keys; values redacted unless asked for
- **`set_secure_storage_key`** — write or delete a key (needs --allow-destructive)

The full tool reference is
[TOOLS.generated.md](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md).
FlutterPilot works in debug builds; `FlutterPilot.initialize()` does nothing
in release.
