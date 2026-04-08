import 'dart:convert';
import 'dart:developer';
import 'package:riverpod/riverpod.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// A Riverpod observer that tracks provider changes and enables state injection.
base class RiverpodPilotObserver extends ProviderObserver {
  static final Map<String, dynamic> _states = {};
  static final Map<String, ProviderBase> _providers = {};
  static ProviderContainer? _lastContainer;

  RiverpodPilotObserver() {
    _registerExtension();
  }

  void _registerExtension() {
    // Register the state setter with FlutterPilot SDK
    FlutterPilot.registerStateSetter('riverpod', (name, value) async {
      final container = _lastContainer;
      if (container == null) throw 'No ProviderContainer found. Is the app running?';
      
      final provider = _providers[name];
      if (provider == null) throw 'Provider "$name" not found or not yet active.';

      // Attempt to find a notifier or state to update
      try {
        // Use dynamic to access 'notifier' which exists on most Riverpod providers 
        // but is not defined on the base ProviderBase class.
        final dynamic dynamicProvider = provider;
        final dynamic notifier = container.read(dynamicProvider.notifier);
        
        if (notifier is StateController) {
          notifier.state = value;
        } else {
          // Fallback for Notifiers and other types that expose a settable state
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

    // Legacy direct extension for backward compatibility
    try {
      registerExtension('ext.flutterpilot.getRiverpodStates', (method, parameters) async {
        return ServiceExtensionResponse.result(json.encode({'states': _states}));
      });
    } catch (e) {
      // Extension already registered (e.g., multiple observer instances).
    }
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
