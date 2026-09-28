# flutterpilot_supabase

[FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin for apps using
**supabase_flutter**: lets an AI agent (Claude Code, Cursor, VS Code…) see and drive
Supabase state in the running app through the FlutterPilot MCP server.

## Install

In your app folder, `flutterpilot init` detects supabase_flutter and adds this plugin
(with `flutterpilot_sdk`). By hand:

```bash
flutter pub add flutterpilot_sdk flutterpilot_supabase
```

## Wire it

The plugin does nothing until the app registers it, once, at startup:

```dart
import 'package:flutterpilot_supabase/flutterpilot_supabase.dart';

SupabasePilotInspector.register(Supabase.instance.client);
```

`flutterpilot doctor` checks the wiring — and, while the app runs, that it
registered.

## Tools it adds

Listed by the server only once the app has registered the plugin:

- **`get_supabase_auth`** — session and user as the app sees them
- **`query_supabase_table`** — read a table with the app's own session and RLS
- **`supabase_session`** — refresh or sign out (needs --allow-destructive)

The full tool reference is
[TOOLS.generated.md](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md).
FlutterPilot works in debug builds; `FlutterPilot.initialize()` does nothing
in release.
