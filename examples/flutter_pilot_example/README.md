# FlutterPilot Example App

A demo Flutter application showcasing all FlutterPilot features.

## Running

```bash
cd examples/flutter_pilot_example
flutter run
```

Copy the VM Service URI from the output, then start the MCP server:

```bash
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri <vm-service-uri>
```

## Features Demonstrated

- **SDK Initialization** — `FlutterPilot.initialize()` in `main.dart`
- **Riverpod Integration** — Counter provider with `RiverpodPilotObserver`
- **Bloc Integration** — Theme cubit with `BlocPilotObserver`
- **Dio Integration** — HTTP client with `DioPilotInterceptor`
- **Navigation Tracking** — `NavigationPilotObserver` on MaterialApp
- **State Injection** — Runtime state modification via AI agents
