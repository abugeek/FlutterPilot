import 'dart:convert';
import 'dart:developer';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// A Bloc observer that tracks state transitions and enables state injection.
class BlocPilotObserver extends BlocObserver {
  static final Map<String, dynamic> _blocStates = {};
  static final Map<String, BlocBase> _activeBlocs = {};

  BlocPilotObserver() {
    _registerExtension();
  }

  void _registerExtension() {
    FlutterPilot.registerStateSetter('bloc', (name, value) async {
      final bloc = _activeBlocs[name];
      if (bloc == null) throw 'Bloc "$name" not found or not yet active.';

      try {
        // Blocs don't allow direct state emission from outside easily.
        // We use dynamic access to call the protected 'emit' method.
        final dynamic dynamicBloc = bloc;
        dynamicBloc.emit(value);
        return {'status': 'success', 'name': name, 'newState': value};
      } catch (e) {
        throw 'Failed to set state for "$name": $e. Ensure your Bloc/Cubit allows dynamic emission.';
      }
    });

    try {
      registerExtension('ext.flutterpilot.getBlocStates', (method, parameters) async {
        return ServiceExtensionResponse.result(json.encode({'states': _blocStates}));
      });
    } catch (e) {
      // Extension already registered (e.g., multiple observer instances).
    }
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
