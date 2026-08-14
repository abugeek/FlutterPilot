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
  static final Map<String, dynamic> _providers = {};
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
    FlutterPilot.registerCapability(
      'riverpod',
      version: '1',
      extensions: ['ext.flutterpilot.getRiverpodStates'],
    );
    if (!FlutterPilot.isInitialized) {
      debugPrint(
        'FlutterPilot: RiverpodPilotObserver registered before '
        'FlutterPilot.initialize(). Call FlutterPilot.initialize() first.',
      );
    }

    FlutterPilot.registerStateSetter('riverpod', (name, value) async {
      final container = _containers[name];
      if (container == null) {
        throw Exception(
          'No ProviderContainer found for "$name". Is the app running?',
        );
      }

      final provider = _providers[name];
      if (provider == null) {
        throw Exception('Provider "$name" not found or not yet active.');
      }

      try {
        final dynamic dynamicProvider = provider;
        final dynamic notifier = container.read(dynamicProvider.notifier);

        try {
          notifier.state = value;
        } catch (e) {
          throw Exception(
            'Provider "$name" (type: ${notifier.runtimeType}) does not support direct state injection: $e',
          );
        }
        return {'status': 'success', 'name': name, 'newValue': value};
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Failed to set state for "$name": $e');
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

  /// Clears all tracked state. Call on hot-restart to prevent stale data.
  static void reset() {
    _states.clear();
    _providers.clear();
    _containers.clear();
    _initialized = false;
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    final name = context.provider.runtimeType.toString();
    _providers[name] = context.provider;
    _containers[name] = context.container;

    _states[name] = {
      'value': newValue?.toString() ?? 'null',
      'type': newValue.runtimeType.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    _cleanStaleEntries();
    FlutterPilot.logStateChange('riverpod', name, newValue);
  }

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    final name = context.provider.runtimeType.toString();
    _providers[name] = context.provider;
    _containers[name] = context.container;

    _states[name] = {
      'value': value?.toString() ?? 'null',
      'type': value.runtimeType.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    FlutterPilot.logStateChange('riverpod', name, value);
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    final name = context.provider.runtimeType.toString();
    _states.remove(name);
    _providers.remove(name);
    _containers.remove(name);
  }
}
