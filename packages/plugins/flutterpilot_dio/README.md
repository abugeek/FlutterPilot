# flutterpilot_dio

[FlutterPilot](https://github.com/abugeek/FlutterPilot) plugin for apps using
**dio**: lets an AI agent (Claude Code, Cursor, VS Code…) see and drive
Dio state in the running app through the FlutterPilot MCP server.

## Install

In your app folder, `flutterpilot init` detects dio and adds this plugin
(with `flutterpilot_sdk`). By hand:

```bash
flutter pub add flutterpilot_sdk flutterpilot_dio
```

## Wire it

The plugin does nothing until the app registers it, once, at startup:

```dart
import 'package:flutterpilot_dio/flutterpilot_dio.dart';

DioPilotInterceptor.register(); // in main(), so the tools are listed before the first request
dio.interceptors.add(DioPilotInterceptor()); // on every Dio you create
```

`flutterpilot doctor` checks the wiring — and, while the app runs, that it
registered.

## Tools it adds

Listed by the server only once the app has registered the plugin:

- **`get_network_logs`** — recent requests and responses: method, URL, status, timing, truncated and redacted bodies, errors; mocked ones marked
- **`mock_http_response`** — answer matching requests with a canned status/body (test error handling without a backend)
- **`simulate_network`** — slow 3G, fast 4G, offline or normal for requests made through Dio

The full tool reference is
[TOOLS.generated.md](https://github.com/abugeek/FlutterPilot/blob/main/TOOLS.generated.md).
FlutterPilot works in debug builds; `FlutterPilot.initialize()` does nothing
in release.
