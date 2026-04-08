# FlutterPilot Riverpod Plugin

Expose Riverpod provider states to FlutterPilot for AI inspection and state injection.

## Setup

```yaml
dependencies:
  flutterpilot_riverpod:
    path: packages/plugins/flutterpilot_riverpod
```

```dart
import 'package:flutterpilot_riverpod/flutterpilot_riverpod.dart';

ProviderScope(
  observers: [RiverpodPilotObserver()],
  child: MyApp(),
)
```

## What It Exposes

- **`get_riverpod_states`** — All active provider values with types and timestamps
- **`set_state(type: 'riverpod', name, value)`** — Inject state into a running provider via the SDK's unified state setter
