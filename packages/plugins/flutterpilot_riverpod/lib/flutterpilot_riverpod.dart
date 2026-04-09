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
class RiverpodPilotObserver extends ProviderObserver {
  static final Map<String, dynamic> _states = {};
  static final Map<String, ProviderBase> _providers = {};
  static final Map<String, ProviderContainer> _containers = {};
  static bool _initialized = false;
  static const int _maxEntries = 100;

  RiverpodPilotObserver() {
    if (!_initialized) {
      _initialized = true;
      _registerExtension();
    }
  }

  void _registerExtension() {
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        'FlutterPilot: RiverpodPilotObserver registered before '
        'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.',
      );
    }

    FlutterPilot.registerStateSetter('riverpod', (name, value) async {
      final container = _containers[name];
      if (container == null) {
        throw 'No ProviderContainer found for "$name". Is the app running?';
      }

      final provider = _providers[name];
      if (provider == null) {
        throw 'Provider "$name" not found or not yet active.';
      }

      try {
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

    FlutterPilot.registerStateReader('riverpod', (name) {
      final entry = _states[name];
      if (entry == null) return null;
      return entry['value']?.toString();
    });

    registerExtension('ext.flutterpilot.getRiverpodStates', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(json.encode({'states': _states}));
    });
  }

  static void _cleanStaleEntries() {
    if (_states.length >= _maxEntries) {
      final staleKeys = _states.keys
          .where((k) => !_providers.containsKey(k))
          .toList();
      for (final k in staleKeys) {
        _states.remove(k);
      }
    }
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    final name = provider.runtimeType.toString();
    _providers[name] = provider;
    _containers[name] = container;

    _states[name] = {
      'value': newValue.toString(),
      'type': newValue.runtimeType.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    _cleanStaleEntries();
    FlutterPilot.logStateChange('riverpod', name, newValue);
  }

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    final name = provider.runtimeType.toString();
    _providers[name] = provider;
    _containers[name] = container;

    _states[name] = {
      'value': value.toString(),
      'type': value.runtimeType.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    FlutterPilot.logStateChange('riverpod', name, value);
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    final name = provider.runtimeType.toString();
    _states.remove(name);
    _providers.remove(name);
    _containers.remove(name);
  }
}
