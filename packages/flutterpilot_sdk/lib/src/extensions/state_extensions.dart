part of '../../flutterpilot_sdk.dart';

/// State management service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `setState` — Inject a state value via a registered setter
/// - `waitForState` — Poll until a state value matches
/// - `setLocale` — Override the app locale at runtime
/// - `setTextScaleFactor` — Override the text scale factor
/// - `saveStateSnapshot` — Capture current state into a named snapshot
/// - `restoreStateSnapshot` — Rewind app state back to a named snapshot
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

    // -- ext.flutterpilot.saveStateSnapshot -----------------------------------
    registerExtension('ext.flutterpilot.saveStateSnapshot', (
      method,
      parameters,
    ) async {
      final name = parameters['name'] ?? 'snapshot_${DateTime.now().millisecondsSinceEpoch}';
      final snapshot = StateSnapshotManager.saveSnapshot(name);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'saved', 'snapshot': snapshot.toJson()}),
      );
    });

    // -- ext.flutterpilot.restoreStateSnapshot --------------------------------
    registerExtension('ext.flutterpilot.restoreStateSnapshot', (
      method,
      parameters,
    ) async {
      final name = parameters['name'];
      if (name == null || name.isEmpty) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing snapshot name',
        );
      }
      final success = await StateSnapshotManager.restoreSnapshot(name);
      if (!success) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Snapshot not found: $name',
        );
      }
      return ServiceExtensionResponse.result(
        json.encode({'status': 'restored', 'name': name}),
      );
    });

    // -- ext.flutterpilot.listStateSnapshots ----------------------------------
    registerExtension('ext.flutterpilot.listStateSnapshots', (
      method,
      parameters,
    ) async {
      final list = StateSnapshotManager.listSnapshots();
      return ServiceExtensionResponse.result(
        json.encode({'snapshots': list}),
      );
    });

    // -- ext.flutterpilot.deleteStateSnapshot --------------------------------
    registerExtension('ext.flutterpilot.deleteStateSnapshot', (
      method,
      parameters,
    ) async {
      final name = parameters['name'];
      if (name == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing snapshot name',
        );
      }
      final deleted = StateSnapshotManager.deleteSnapshot(name);
      return ServiceExtensionResponse.result(
        json.encode({'status': deleted ? 'deleted' : 'not_found', 'name': name}),
      );
    });
  }
}
