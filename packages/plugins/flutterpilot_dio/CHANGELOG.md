## Unreleased

- `mock_http_response(error: "timeout" | "connection")`: `DioPilotInterceptor.mock(pattern, error: ...)` fails matching requests with a receive timeout or a connection error instead of a response; such failures are marked as mocked in `get_network_logs`.

## 0.1.0

- First release: `get_network_logs`, `mock_http_response`, `simulate_network` for apps using dio.
