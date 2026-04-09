import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// A [BlocObserver] that tracks Bloc/Cubit state transitions for FlutterPilot.
///
/// Registers a `bloc` state setter with [FlutterPilot] and exposes a
/// `ext.flutterpilot.getBlocStates` service extension for reading current
/// Bloc states.
///
/// ## Setup
/// ```dart
/// void main() {
///   FlutterPilot.initialize();
///   Bloc.observer = BlocPilotObserver();
///   runApp(const MyApp());
/// }
/// ```
class BlocPilotObserver extends BlocObserver {
  static final Map<String, dynamic> _blocStates = {};
  static final Map<String, BlocBase> _activeBlocs = {};
  static bool _initialized = false;
  static const int _maxEntries = 100;

  BlocPilotObserver() {
    if (!_initialized) {
      _initialized = true;
      _registerExtension();
    }
  }

  void _registerExtension() {
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        'FlutterPilot: BlocPilotObserver registered before '
        'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.',
      );
    }

    FlutterPilot.registerStateSetter('bloc', (name, value) async {
      // Try unique key first, then fall back to simple name prefix
      BlocBase? bloc = _activeBlocs[name];
      if (bloc == null) {
        for (final entry in _activeBlocs.entries) {
          if (entry.key.startsWith('$name#')) {
            bloc = entry.value;
            break;
          }
        }
      }
      if (bloc == null) {
        throw Exception('Bloc "$name" not found or not yet active.');
      }

      try {
        final dynamic dynamicBloc = bloc;
        dynamicBloc.emit(value);
        return {'status': 'success', 'name': name, 'newState': value};
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception(
          'Failed to set state for "$name": $e. Ensure your Bloc/Cubit allows dynamic emission.',
        );
      }
    });

    FlutterPilot.registerStateReader('bloc', (name) {
      final entry = _blocStates[name];
      if (entry == null) return null;
      return entry['state']?.toString();
    });

    registerExtension('ext.flutterpilot.getBlocStates', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({'states': _blocStates}),
      );
    });
  }

  static void _cleanStaleEntries() {
    if (_blocStates.length >= _maxEntries * 2) {
      final staleKeys = _blocStates.keys
          .where((k) => k.contains('#') && !_activeBlocs.containsKey(k))
          .toList();
      for (final k in staleKeys) {
        _blocStates.remove(k);
      }
    }
  }

  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    final uniqueKey = '${bloc.runtimeType}#${identityHashCode(bloc)}';
    _activeBlocs[uniqueKey] = bloc;

    final stateEntry = {
      'state': change.nextState?.toString() ?? 'null',
      'type': change.nextState.runtimeType.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    _blocStates[uniqueKey] = stateEntry;
    // Also store by simple name for backward-compat lookup
    final simpleName = bloc.runtimeType.toString();
    _blocStates[simpleName] = stateEntry;

    _cleanStaleEntries();
    FlutterPilot.logStateChange('bloc', simpleName, change.nextState);
  }

  @override
  void onCreate(BlocBase bloc) {
    super.onCreate(bloc);
    final uniqueKey = '${bloc.runtimeType}#${identityHashCode(bloc)}';
    _activeBlocs[uniqueKey] = bloc;

    final stateEntry = {
      'state': bloc.state?.toString() ?? 'null',
      'type': bloc.state.runtimeType.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    _blocStates[uniqueKey] = stateEntry;
    final simpleName = bloc.runtimeType.toString();
    _blocStates[simpleName] = stateEntry;

    FlutterPilot.logStateChange('bloc', simpleName, bloc.state);
  }

  @override
  void onClose(BlocBase bloc) {
    final uniqueKey = '${bloc.runtimeType}#${identityHashCode(bloc)}';
    _activeBlocs.remove(uniqueKey);
    _blocStates.remove(uniqueKey);
    // Keep the simple name entry if another instance exists
    final simpleName = bloc.runtimeType.toString();
    if (!_activeBlocs.values.any(
      (b) => b.runtimeType.toString() == simpleName,
    )) {
      _blocStates.remove(simpleName);
    }
    super.onClose(bloc);
  }
}
