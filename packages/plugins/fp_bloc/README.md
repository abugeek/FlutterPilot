# fp_bloc

[FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin for apps using
**flutter_bloc / bloc**: lets an AI agent (Claude Code, Cursor, VS Code…) see and drive
Bloc state in the running app through the FlutterPilot MCP server.

## Install

In your app folder, `flutterpilot init` detects flutter_bloc and adds this plugin
(with `fp_sdk`). By hand:

```bash
flutter pub add fp_sdk fp_bloc
```

## Wire it

The plugin does nothing until the app registers it, once, at startup:

```dart
import 'package:fp_bloc/fp_bloc.dart';

Bloc.observer = BlocPilotObserver();
```

`flutterpilot doctor` checks the wiring — and, while the app runs, that it
registered.

## Tools it adds

Listed by the server only once the app has registered the plugin:

- **`get_state`** — current state of every Bloc/Cubit the app created
- **`set_state`** — replace a Cubit/Bloc state in memory to reach a screen quickly

The full tool reference is
[TOOLS.generated.md](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md).
FlutterPilot works in debug builds; `FlutterPilot.initialize()` does nothing
in release.
