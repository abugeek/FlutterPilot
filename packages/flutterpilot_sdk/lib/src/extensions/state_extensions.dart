part of '../../flutterpilot_sdk.dart';

/// State management service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `setState` — Inject a state value via a registered setter
/// - `waitForState` — Poll until a state value matches
/// - `setLocale` — Override the app locale at runtime
/// - `setTextScaleFactor` — Override the text scale factor
extension _StateExtensions on FlutterPilot {
  static void register() {
    // -- ext.flutterpilot.setState --------------------------------------------
    registerExtension('ext.flutterpilot.setState', (method, parameters) async {
      final type = parameters['type'];
      final name = parameters['name'];
      final valueJson = parameters['value'];

      if (type == null || name == null || valueJson == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing type, name, or value',
        );
      }

      if (!FlutterPilot._stateSetters.containsKey(type)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No setter registered for type: $type',
        );
      }

      try {
        final dynamic value = json.decode(valueJson);
        final result = await FlutterPilot._stateSetters[type]!(name, value);
        return ServiceExtensionResponse.result(
          json.encode({
            'status': 'success',
            'result': FlutterPilot._safeJsonEncode(result),
          }),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'State injection failed: $e',
        );
      }
    });

    // -- ext.flutterpilot.waitForState ----------------------------------------
    registerExtension('ext.flutterpilot.waitForState', (
      method,
      parameters,
    ) async {
      final type = parameters['type'];
      final name = parameters['name'];
      final expectedValue = parameters['expectedValue'];
      final timeoutMs = int.tryParse(parameters['timeoutMs'] ?? '5000') ?? 5000;

      if (type == null || name == null || expectedValue == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing type, name, or expectedValue',
        );
      }
      final reader = FlutterPilot._stateReaders[type];
      if (reader == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No state reader registered for type: $type. '
          'Ensure the plugin is initialised (e.g. RiverpodPilotObserver / BlocPilotObserver).',
        );
      }

      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
      String? lastValue;
      while (DateTime.now().isBefore(deadline)) {
        lastValue = reader(name);
        if (lastValue != null && lastValue.contains(expectedValue)) {
          return ServiceExtensionResponse.result(
            json.encode({
              'status': 'matched',
              'type': type,
              'name': name,
              'value': lastValue,
            }),
          );
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'Timeout: $type "$name" did not reach "$expectedValue" within '
        '${timeoutMs}ms (last value: "$lastValue")',
      );
    });

    // -- ext.flutterpilot.setLocale -------------------------------------------
    registerExtension('ext.flutterpilot.setLocale', (method, parameters) async {
      final code = parameters['locale'];
      if (code == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing locale',
        );
      }
      try {
        if (code == 'default') {
          FlutterPilot.localeNotifier.value = null;
        } else {
          final parts = code.split('_');
          FlutterPilot.localeNotifier.value = parts.length > 1
              ? ui.Locale(parts[0], parts[1])
              : ui.Locale(parts[0]);
        }
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success'}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Error: $e',
        );
      }
    });

    // -- ext.flutterpilot.setTextScaleFactor ----------------------------------
    registerExtension('ext.flutterpilot.setTextScaleFactor', (
      method,
      parameters,
    ) async {
      final scaleStr = parameters['scale'];
      if (scaleStr == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: scale',
        );
      }
      final scale = double.tryParse(scaleStr);
      if (scale == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'scale must be a numeric value',
        );
      }
      FlutterPilot.textScaleNotifier.value = scale <= 0 ? null : scale;
      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'success',
          'scale': FlutterPilot.textScaleNotifier.value ?? 'default',
        }),
      );
    });
  }
}
