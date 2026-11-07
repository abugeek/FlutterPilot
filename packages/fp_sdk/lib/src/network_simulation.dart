import 'network_simulation_stub.dart'
    if (dart.library.io) 'network_simulation_io.dart'
    as io;

/// The network condition `simulate_network` puts every request under. Read
/// by the `dart:io` client wrapper installed by [install] (so
/// `package:http`, Dio and raw `HttpClient` all feel it) and by
/// `DioPilotInterceptor`, whose mocked answers never reach `dart:io`.
class NetworkSimulation {
  static bool offline = false;
  static Duration? latency;
  static double errorRate = 0.0;
  static int? statusCode;
  static int _counter = 0;

  /// The preset latencies: `slow_3g`, `fast_4g`.
  static const presets = {'slow_3g': 1500, 'fast_4g': 100};

  /// Whether `dart:io` clients are wrapped. False on web, or when the app
  /// replaced `HttpOverrides.global` after FlutterPilot's was installed.
  static bool get intercepting => io.httpOverridesActive;

  static void install() => io.installHttpOverrides();

  /// Determines whether a simulated chaos failure should be triggered.
  static bool shouldFail() {
    if (errorRate <= 0.0) return false;
    if (errorRate >= 1.0) return true;
    _counter++;
    return ((_counter % 100) / 100.0) < errorRate;
  }

  /// Sets the condition: [offline], [latency] to wait before a request
  /// goes out, and chaos [errorRate] / [statusCode].
  static void set({
    required bool offline,
    Duration? latency,
    double errorRate = 0.0,
    int? statusCode,
  }) {
    NetworkSimulation.offline = offline;
    NetworkSimulation.latency = latency;
    NetworkSimulation.errorRate = errorRate.clamp(0.0, 1.0);
    NetworkSimulation.statusCode = statusCode;
  }

  /// Resets all network simulation conditions to normal.
  static void reset() {
    set(offline: false, latency: null, errorRate: 0.0, statusCode: null);
  }
}
