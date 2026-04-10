import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void _safeRegisterExtension(
  String method,
  Future<ServiceExtensionResponse> Function(String, Map<String, String>)
      handler,
) {
  try {
    registerExtension(method, handler);
  } on ArgumentError {
    // Already registered — safe to ignore during re-initialization.
  }
}

/// FlutterPilot plugin that exposes network connectivity state to AI agents.
///
/// Provides visibility into:
/// - **Current status**: wifi, mobile, none, ethernet, vpn, bluetooth
/// - **Connectivity history**: timestamped log of transitions
/// - **Simulated offline**: override connectivity for testing
///
/// ## Setup
/// ```dart
/// ConnectivityPilotInspector.register();
/// ```
class ConnectivityPilotInspector {
  ConnectivityPilotInspector._();

  static bool _registered = false;
  static final List<Map<String, dynamic>> _history = [];
  static StreamSubscription<List<ConnectivityResult>>? _sub;
  static List<ConnectivityResult> _currentResults = [];
  static bool _simulatedOffline = false;
  static const int _maxHistory = 100;

  /// Registers the connectivity inspector with FlutterPilot.
  ///
  /// Automatically starts listening to connectivity changes:
  /// ```dart
  /// ConnectivityPilotInspector.register();
  /// ```
  static void register() {
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        '[FlutterPilot] ConnectivityPilotInspector.register called before '
        'FlutterPilot.initialize(). Extensions will not be registered.',
      );
      return;
    }
    if (_registered) return;
    _registered = true;
    _startListening();
    _registerExtensions();
  }

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    _sub?.cancel();
    _sub = null;
    _history.clear();
    _currentResults = [];
    _simulatedOffline = false;
    _registered = false;
  }

  /// Whether offline simulation is currently active.
  ///
  /// App code can check this to simulate offline behavior:
  /// ```dart
  /// if (ConnectivityPilotInspector.isSimulatedOffline) {
  ///   throw SocketException('Simulated offline by FlutterPilot');
  /// }
  /// ```
  static bool get isSimulatedOffline => _simulatedOffline;

  static void _startListening() {
    final connectivity = Connectivity();
    connectivity.checkConnectivity().then((results) {
      _currentResults = results;
      _addHistory(results);
    });
    _sub = connectivity.onConnectivityChanged.listen((results) {
      _currentResults = results;
      _addHistory(results);
    });
  }

  static void _addHistory(List<ConnectivityResult> results) {
    _history.add({
      'results': results.map((r) => r.name).toList(),
      'timestamp': DateTime.now().toIso8601String(),
      'simulatedOffline': _simulatedOffline,
    });
    while (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
  }

  static void _registerExtensions() {
    // -- ext.flutterpilot.getConnectivity --------------------------------------
    _safeRegisterExtension('ext.flutterpilot.getConnectivity', (
      method,
      parameters,
    ) async {
      final hasNone = _currentResults.isEmpty ||
          _currentResults.contains(ConnectivityResult.none);

      return ServiceExtensionResponse.result(json.encode({
        'connectivity': _currentResults.map((r) => r.name).toList(),
        'isOnline': !hasNone && !_simulatedOffline,
        'simulatedOffline': _simulatedOffline,
        'hasWifi': _currentResults.contains(ConnectivityResult.wifi),
        'hasMobile': _currentResults.contains(ConnectivityResult.mobile),
        'hasEthernet': _currentResults.contains(ConnectivityResult.ethernet),
        'hasVpn': _currentResults.contains(ConnectivityResult.vpn),
      }));
    });

    // -- ext.flutterpilot.getConnectivityHistory --------------------------------
    _safeRegisterExtension('ext.flutterpilot.getConnectivityHistory', (
      method,
      parameters,
    ) async {
      final limitStr = parameters['limit'];
      final limit = (int.tryParse(limitStr ?? '') ?? _maxHistory)
          .clamp(1, _maxHistory);
      final entries = _history.length > limit
          ? _history.sublist(_history.length - limit)
          : _history;

      return ServiceExtensionResponse.result(json.encode({
        'history': entries,
        'count': entries.length,
        'total': _history.length,
      }));
    });

    // -- ext.flutterpilot.simulateOffline --------------------------------------
    _safeRegisterExtension('ext.flutterpilot.simulateOffline', (
      method,
      parameters,
    ) async {
      final enabled = parameters['enabled'] ?? 'true';
      _simulatedOffline = enabled.toLowerCase() == 'true';
      _addHistory(_currentResults); // log the simulation change

      return ServiceExtensionResponse.result(json.encode({
        'status': 'success',
        'simulatedOffline': _simulatedOffline,
      }));
    });
  }
}
