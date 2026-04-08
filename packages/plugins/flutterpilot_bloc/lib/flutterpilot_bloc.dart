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

  BlocPilotObserver() {
    if (!_initialized) {
      _initialized = true;
      _registerExtension();
    }
  }

  void _registerExtension() {
    if (!FlutterPilot.isInitialized) {
      debugPrint('FlutterPilot: BlocPilotObserver registered before '
          'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.');
    }

    FlutterPilot.registerStateSetter('bloc', (name, value) async {
      final bloc = _activeBlocs[name];
      if (bloc == null) throw 'Bloc "$name" not found or not yet active.';

      try {
        // Use dynamic access to call the protected 'emit' method.
        final dynamic dynamicBloc = bloc;
        dynamicBloc.emit(value);
        return {'status': 'success', 'name': name, 'newState': value};
      } catch (e) {
        throw 'Failed to set state for "$name": $e. Ensure your Bloc/Cubit allows dynamic emission.';
      }
    });

    registerExtension('ext.flutterpilot.getBlocStates', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({'states': _blocStates}));
    });
  }

  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    final name = bloc.runtimeType.toString();
    _activeBlocs[name] = bloc;
    
    _blocStates[name] = {
      'state': change.nextState.toString(),
      'type': change.nextState.runtimeType.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    FlutterPilot.logStateChange('bloc', name, change.nextState);
  }

  @override
  void onCreate(BlocBase bloc) {
    super.onCreate(bloc);
    final name = bloc.runtimeType.toString();
    _activeBlocs[name] = bloc;

    _blocStates[name] = {
      'state': bloc.state.toString(),
      'type': bloc.state.runtimeType.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    FlutterPilot.logStateChange('bloc', name, bloc.state);
  }

  @override
  void onClose(BlocBase bloc) {
    super.onClose(bloc);
    _activeBlocs.remove(bloc.runtimeType.toString());
  }
}
