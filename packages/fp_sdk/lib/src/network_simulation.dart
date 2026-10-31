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

  /// The preset latencies: `slow_3g`, `fast_4g`.
  static const presets = {'slow_3g': 1500, 'fast_4g': 100};

  /// Whether `dart:io` clients are wrapped. False on web, or when the app
  /// replaced `HttpOverrides.global` after FlutterPilot's was installed.
  static bool get intercepting => io.httpOverridesActive;

  static void install() => io.installHttpOverrides();

  /// Sets the condition: [offline], and [latency] to wait before a request
  /// goes out (null: none).
  static void set({required bool offline, Duration? latency}) {
    NetworkSimulation.offline = offline;
    NetworkSimulation.latency = latency;
  }
}
