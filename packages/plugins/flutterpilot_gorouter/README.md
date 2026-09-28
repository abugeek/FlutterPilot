# flutterpilot_gorouter

[FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin for apps using
**go_router**: lets an AI agent (Claude Code, Cursor, VS Code…) see and drive
GoRouter state in the running app through the FlutterPilot MCP server.

## Install

In your app folder, `flutterpilot init` detects go_router and adds this plugin
(with `flutterpilot_sdk`). By hand:

```bash
flutter pub add flutterpilot_sdk flutterpilot_gorouter
```

## Wire it

The plugin does nothing until the app registers it, once, at startup:

```dart
import 'package:flutterpilot_gorouter/flutterpilot_gorouter.dart';

GoRouterPilotInspector.register(router);
```

`flutterpilot doctor` checks the wiring — and, while the app runs, that it
registered.

## Tools it adds

Listed by the server only once the app has registered the plugin:

- **`get_navigation_stack`** — full locations (/story/42), the route table and history
- **`navigate_to`** — go / push / replace through the app's GoRouter

The full tool reference is
[TOOLS.generated.md](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md).
FlutterPilot works in debug builds; `FlutterPilot.initialize()` does nothing
in release.
