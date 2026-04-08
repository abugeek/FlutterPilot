# FlutterPilot Bloc Plugin

Expose Bloc/Cubit states to FlutterPilot for AI inspection and state injection.

## Setup

```yaml
dependencies:
  flutterpilot_bloc:
    path: packages/plugins/flutterpilot_bloc
```

```dart
import 'package:flutterpilot_bloc/flutterpilot_bloc.dart';

Bloc.observer = BlocPilotObserver();
```

## What It Exposes

- **`get_bloc_states`** — All active Bloc/Cubit states with types and timestamps
- **`set_state(type: 'bloc', name, value)`** — Inject state into a running Cubit via the SDK's unified state setter
