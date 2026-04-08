import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:riverpod/riverpod.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// A [ProviderObserver] that tracks Riverpod provider changes for FlutterPilot.
///
/// Registers a `riverpod` state setter with [FlutterPilot] and exposes a
/// `ext.flutterpilot.getRiverpodStates` service extension for reading current
/// provider states.
///
/// ## Setup
/// ```dart
/// void main() {
///   FlutterPilot.initialize();
///   runApp(ProviderScope(
///     observers: [RiverpodPilotObserver()],
///     child: const MyApp(),
///   ));
/// }
/// ```
base class RiverpodPilotObserver extends ProviderObserver {
  static final Map<String, dynamic> _states = {};
  static final Map<String, ProviderBase> _providers = {};
  static ProviderContainer? _lastContainer;
  static bool _initialized = false;

  RiverpodPilotObserver() {
    if (!_initialized) {
      _initialized = true;
      _registerExtension();
    }
  }

  void _registerExtension() {
    if (!FlutterPilot.isInitialized) {
      debugPrint('FlutterPilot: RiverpodPilotObserver registered before '
          'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.');
    }

    FlutterPilot.registerStateSetter('riverpod', (name, value) async {
      final container = _lastContainer;
      if (container == null) throw 'No ProviderContainer found. Is the app running?';
      
      final provider = _providers[name];
      if (provider == null) throw 'Provider "$name" not found or not yet active.';

      try {
        // Use dynamic to access 'notifier' which exists on most Riverpod
        // providers but is not defined on the base ProviderBase class.
        final dynamic dynamicProvider = provider;
        final dynamic notifier = container.read(dynamicProvider.notifier);
        
        if (notifier is StateController) {
          notifier.state = value;
        } else {
          try {
            notifier.state = value;
          } catch (e) {
            throw 'Provider "$name" (type: ${notifier.runtimeType}) does not support direct state injection: $e';
          }
        }
        return {'status': 'success', 'name': name, 'newValue': value};
      } catch (e) {
        throw 'Failed to set state for "$name": $e';
      }
    });

    registerExtension('ext.flutterpilot.getRiverpodStates', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({'states': _states}));
    });
  }

  @override
  void didUpdateProvider(ProviderBase<Object?> provider, Object? previousValue, Object? newValue, ProviderContainer container) {
    _lastContainer = container;
    final name = provider.runtimeType.toString();
    _providers[name] = provider;
    
    _states[name] = {
      'value': newValue.toString(),
      'type': newValue.runtimeType.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    FlutterPilot.logStateChange('riverpod', name, newValue);
  }

  @override
  void didAddProvider(ProviderBase<Object?> provider, Object? value, ProviderContainer container) {
    _lastContainer = container;
    final name = provider.runtimeType.toString();
    _providers[name] = provider;

    _states[name] = {
      'value': value.toString(),
      'type': value.runtimeType.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    FlutterPilot.logStateChange('riverpod', name, value);
  }
}
