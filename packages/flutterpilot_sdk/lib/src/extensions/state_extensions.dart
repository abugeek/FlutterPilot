part of '../../flutterpilot_sdk.dart';

/// State management service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `setState` — Inject a state value via a registered setter
/// - `waitForState` — Poll until a state value matches
/// - `setLocale` — Override the app locale at runtime
/// - `setTextScaleFactor` — Override the text scale factor
/// - `listStateSnapshots` — List all saved snapshots
/// - `deleteStateSnapshot` — Delete a saved snapshot
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
        dynamic value;
        try {
          value = json.decode(valueJson);
        } catch (_) {
          value = valueJson;
        }
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

    // -- ext.flutterpilot.batchSetState ---------------------------------------
    registerExtension('ext.flutterpilot.batchSetState', (
      method,
      parameters,
    ) async {
      final type = parameters['type'] ?? 'riverpod';
      final statesJson = parameters['states'];

      if (statesJson == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing states JSON parameter',
        );
      }

      final setter = FlutterPilot._stateSetters[type];
      if (setter == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No setter registered for type: $type',
        );
      }

      try {
        final decoded = json.decode(statesJson);
        if (decoded is! Map) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'States must be a JSON map of key-value pairs',
          );
        }

        final results = <String, dynamic>{};
        for (final entry in decoded.entries) {
          final key = entry.key.toString();
          final val = entry.value;
          final res = await setter(key, val);
          results[key] = FlutterPilot._safeJsonEncode(res);
        }

        return ServiceExtensionResponse.result(
          json.encode({
            'status': 'success',
            'updatedCount': results.length,
            'results': results,
          }),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Batch state injection failed: $e',
        );
      }
    });

    // -- ext.flutterpilot.waitForState ----------------------------------------
    registerExtension('ext.flutterpilot.waitForState', (
      method,
      parameters,
    ) async {
      final type = parameters['type'];
      final name = parameters['name'] ?? parameters['target'];
      final expectedValue =
          parameters['expectedValue'] ??
          parameters['expected'] ??
          parameters['expect'];
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
      final reset = code == 'system' || code == 'default';
      final requested = reset ? null : AppSettingsOverride.parseLocale(code);
      if (!reset && requested == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Not a locale: "$code". Use a tag like "fr", "en-GB" or "zh-Hans-CN", '
          'or "system".',
        );
      }
      final r = await AppSettingsOverride.instance.setLocale(requested);
      final shown = r['locale'] as String?;
      final supported = (r['supported'] as List?)?.join(', ');
      final String status;
      final String? note;
      if (shown == null) {
        status = 'success';
        note =
            'no MaterialApp/CupertinoApp/WidgetsApp found; only code that '
            'listens for device locale changes sees it';
      } else if (requested == null) {
        status = 'success';
        note = 'device locale; the app shows $shown';
      } else if (shown.split('_').first != requested.languageCode) {
        status = 'no_effect';
        note = r['appSetsLocale'] != null
            ? 'the app sets MaterialApp(locale: ${r['appSetsLocale']}) '
                  'itself, so the device locale does not change it'
            : 'the app does not support ${requested.languageCode} '
                  '(supportedLocales: $supported); it shows $shown';
      } else {
        status = 'success';
        note = shown == requested.toString() ? null : 'the app shows $shown';
      }
      return ServiceExtensionResponse.result(
        json.encode({'status': status, 'locale': shown, 'note': ?note}),
      );
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
      final requested = scale <= 0 ? null : scale;
      final r = await AppSettingsOverride.instance.setTextScale(requested);
      final shown = r['scale'] as double?;
      final String status;
      final String? note;
      if (shown == null) {
        status = 'success';
        note = null;
      } else if (requested == null) {
        status = 'success';
        note = 'device scale; the app gets ${shown}x';
      } else if ((shown - requested).abs() > 0.01) {
        status = shown == 1 ? 'no_effect' : 'limited';
        note =
            'the app limits text scaling above its Navigator (e.g. '
            'MediaQuery.withClampedTextScaling in MaterialApp.builder): its '
            'screens get ${shown}x';
      } else {
        status = 'success';
        note = null;
      }
      return ServiceExtensionResponse.result(
        json.encode({'status': status, 'scale': shown, 'note': ?note}),
      );
    });
  }
}
