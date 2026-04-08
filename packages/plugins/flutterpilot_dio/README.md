# FlutterPilot Dio Plugin

Expose Dio network traffic to FlutterPilot for AI inspection.

## Setup

```yaml
dependencies:
  flutterpilot_dio:
    path: packages/plugins/flutterpilot_dio
```

```dart
import 'package:flutterpilot_dio/flutterpilot_dio.dart';

final dio = Dio();
dio.interceptors.add(DioPilotInterceptor());
```

## What It Exposes

- **`get_network_logs`** — Last 50 HTTP requests/responses/errors with method, URI, status code, and timestamps
