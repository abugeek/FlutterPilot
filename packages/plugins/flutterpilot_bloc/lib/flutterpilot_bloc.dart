import 'dart:convert';
import 'dart:developer' show ServiceExtensionResponse;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// A [BlocObserver] that tracks live Blocs/Cubits for FlutterPilot.
///
/// Registers a `bloc` state setter/reader with [FlutterPilot] and exposes a
/// `ext.flutterpilot.getBlocStates` service extension.
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
  /// Live (not yet closed) Blocs/Cubits in creation order.
  static final List<BlocBase<dynamic>> _active = [];
  static bool _initialized = false;

  BlocPilotObserver() {
    register();
  }

  /// Explicitly registers Bloc capabilities with FlutterPilot.
  static void register() {
    if (!_initialized) {
      _initialized = true;
      _registerExtension();
    }
  }

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    _active.clear();
    _initialized = false;
  }

  /// Display name per live bloc: the class name, or `Name#2`, `Name#3`...
  /// when several instances of the same class are alive.
  static Map<String, BlocBase<dynamic>> _named() {
    final byName = <String, BlocBase<dynamic>>{};
    final seen = <String, int>{};
    for (final b in _active) {
      final type = b.runtimeType.toString();
      final n = seen[type] = (seen[type] ?? 0) + 1;
      byName[n == 1 ? type : '$type#$n'] = b;
    }
    return byName;
  }

  /// Current state of every live Bloc/Cubit, read at call time. Each state's
  /// toString() is capped (a state holding a list can be huge).
  static Map<String, Map<String, String>> states() => {
    for (final MapEntry(key: name, value: b) in _named().entries)
      name: {'state': _cap('${b.state}'), 'type': '${b.state.runtimeType}'},
  };

  static const _maxStateChars = 500;
  static String _cap(String s) => s.length <= _maxStateChars
      ? s
      : '${s.substring(0, _maxStateChars)}… (${s.length} chars)';

  /// Emits [value] as the new state of the Bloc/Cubit called [name].
  ///
  /// Works when the state is a bool/num/String/List/Map (JSON can express
  /// it). A class-typed state can't be built from JSON, so this throws with
  /// what to do instead.
  static Map<String, dynamic> inject(String name, Object? value) {
    final named = _named();
    final bloc = named[name];
    if (bloc == null) {
      throw StateError(
        'No live Bloc/Cubit "$name". Live: '
        '${named.isEmpty ? 'none' : named.keys.join(', ')}.',
      );
    }
    final current = bloc.state;
    final next = current is double && value is int ? value.toDouble() : value;
    try {
      (bloc as dynamic).emit(next);
    } on TypeError {
      throw StateError(
        '$name holds a ${current.runtimeType}; a JSON value '
        '(${next.runtimeType}) can\'t be converted to it. set_state '
        'works for bool/num/String/List/Map states — for class states, drive '
        'the UI or dispatch the event that produces the state.',
      );
    }
    return {'name': name, 'newState': '${bloc.state}'};
  }

  static void _registerExtension() {
    FlutterPilot.registerCapability(
      'bloc',
      version: '1',
      extensions: ['ext.flutterpilot.getBlocStates'],
    );
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        'FlutterPilot: BlocPilotObserver registered before '
        'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.',
      );
    }

    FlutterPilot.registerStateSetter(
      'bloc',
      (name, value) async => inject(name, value),
    );
    FlutterPilot.registerStateReader(
      'bloc',
      (name) => states()[name]?['state'],
    );

    registerExtension('ext.flutterpilot.getBlocStates', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(json.encode({'states': states()}));
    });
  }

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    _active.add(bloc);
    FlutterPilot.logStateChange(
      'bloc',
      bloc.runtimeType.toString(),
      bloc.state,
    );
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    FlutterPilot.logStateChange(
      'bloc',
      bloc.runtimeType.toString(),
      change.nextState,
    );
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    _active.remove(bloc);
    super.onClose(bloc);
  }
}
