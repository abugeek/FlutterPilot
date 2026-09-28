# flutterpilot_riverpod

[FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin for apps using
**flutter_riverpod / riverpod**: lets an AI agent (Claude Code, Cursor, VS Code…) see and drive
Riverpod state in the running app through the FlutterPilot MCP server.

## Install

In your app folder, `flutterpilot init` detects flutter_riverpod and adds this plugin
(with `flutterpilot_sdk`). By hand:

```bash
flutter pub add flutterpilot_sdk flutterpilot_riverpod
```

## Wire it

The plugin does nothing until the app registers it, once, at startup:

```dart
import 'package:flutterpilot_riverpod/flutterpilot_riverpod.dart';

ProviderScope(observers: [RiverpodPilotObserver()], child: ...)
```

`flutterpilot doctor` checks the wiring — and, while the app runs, that it
registered.

## Tools it adds

Listed by the server only once the app has registered the plugin:

- **`get_state`** — current value of every provider the app has read
- **`set_state`** — set a provider's state in memory (plain values; names match loosely)

The full tool reference is
[TOOLS.generated.md](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md).
FlutterPilot works in debug builds; `FlutterPilot.initialize()` does nothing
in release.
