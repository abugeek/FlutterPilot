part of '../../flutterpilot_sdk.dart';

/// Recording and custom tool service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `testRecording` — Record actions and assertions for a generated test
/// - `listCustomTools` — List registered custom tools
/// - `callCustomTool` — Invoke a custom tool by name
/// - `getFlightLog` — Read full timeline from continuous FlightRecorder
/// - `clearFlightLog` — Reset the flight recorder buffer
extension _RecordingExtensions on FlutterPilot {
  static void register() {
    // -- ext.flutterpilot.testRecording ---------------------------------------
    // action=start: record from now on; read: the steps so far (and whether
    // recording is on: a hot restart loses them); note: append a step the
    // server knows about (a mocked response); stop: end recording.
    registerExtension('ext.flutterpilot.testRecording', (
      method,
      parameters,
    ) async {
      switch (parameters['action']) {
        case 'start':
          TestRecorder.start();
        case 'note':
          if (TestRecorder.active) {
            TestRecorder.steps.add(
              (json.decode(parameters['step'] ?? '{}') as Map)
                  .cast<String, dynamic>(),
            );
          }
        case 'stop':
          TestRecorder.active = false;
      }
      return ServiceExtensionResponse.result(
        json.encode({
          'active': TestRecorder.active,
          'steps': TestRecorder.steps,
          'secrets': TestRecorder.secrets,
        }),
      );
    });

    // -- ext.flutterpilot.listCustomTools -------------------------------------
    registerExtension('ext.flutterpilot.listCustomTools', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({'tools': FlutterPilot._customTools.keys.toList()}),
      );
    });

    // -- ext.flutterpilot.callCustomTool --------------------------------------
    registerExtension('ext.flutterpilot.callCustomTool', (
      method,
      parameters,
    ) async {
      final name = parameters['name'];
      if (name == null || !FlutterPilot._customTools.containsKey(name)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Tool not found',
        );
      }
      try {
        final result = await FlutterPilot._customTools[name]!(parameters);
        return ServiceExtensionResponse.result(
          json.encode({'result': FlutterPilot._safeJsonEncode(result)}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Error: $e',
        );
      }
    });

    // -- ext.flutterpilot.getFlightLog ----------------------------------------
    registerExtension('ext.flutterpilot.getFlightLog', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode(FlightRecorder.getFlightLogJson()),
      );
    });

    // -- ext.flutterpilot.clearFlightLog --------------------------------------
    registerExtension('ext.flutterpilot.clearFlightLog', (
      method,
      parameters,
    ) async {
      FlightRecorder.clear();
      return ServiceExtensionResponse.result(
        json.encode({'status': 'cleared'}),
      );
    });
  }
}
