# FlutterPilot Example App

A comprehensive demo application showcasing **all** FlutterPilot features — SDK,
navigation tracking, state management (Riverpod + Bloc), network inspection (Dio),
local storage (Hive), and error self-healing.

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

## Screens

| Screen | Route | Demonstrates |
|--------|-------|-------------|
| **Dashboard** | `/` | Auth state (Riverpod), navigation hub |
| **State Injection** | `/state` | Riverpod + Bloc counters, AI-driven state changes |
| **Network & Logs** | `/network` | Dio HTTP requests with `DioPilotInterceptor` |
| **Storage (Hive)** | `/storage` | Key-value storage with `HivePilotInspector` |
| **Chaos (Self-Heal)** | `/chaos` | Intentional crashes for self-heal testing |

## Plugins Demonstrated

- **flutterpilot_sdk** — `FlutterPilot.initialize()` + `NavigationTracker`
- **flutterpilot_riverpod** — `RiverpodPilotObserver` on `ProviderScope`
- **flutterpilot_bloc** — `CounterCubit` state tracking
- **flutterpilot_dio** — `DioPilotInterceptor` captures all HTTP traffic
- **flutterpilot_hive** — `HivePilotInspector.registerBox()` for storage inspection

## AI Agent Service Extensions

Once the MCP server is running, an AI agent can call:

| Extension | Description |
|-----------|-------------|
| `ext.flutterpilot.getWidgetTree` | Full widget tree snapshot |
| `ext.flutterpilot.getNavigationStack` | Current route stack |
| `ext.flutterpilot.getNetworkLogs` | Captured HTTP requests/responses |
| `ext.flutterpilot.getHiveContents` | All registered Hive box data |
| `ext.flutterpilot.getErrors` | Captured Flutter errors |
| `ext.flutterpilot.screenshot` | Current screen capture |
