part of '../../flutterpilot_sdk.dart';

/// Recording and custom tool service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `startRecording` — Begin recording user interactions
/// - `stopRecording` — Stop recording and return captured actions
/// - `listCustomTools` — List registered custom tools
/// - `callCustomTool` — Invoke a custom tool by name
extension _RecordingExtensions on FlutterPilot {
  static void register() {
    // -- ext.flutterpilot.startRecording --------------------------------------
    registerExtension('ext.flutterpilot.startRecording', (
      method,
      parameters,
    ) async {
      FlutterPilot._isRecording = true;
      FlutterPilot._recordedActions.clear();
      return ServiceExtensionResponse.result(
        json.encode({'status': 'started'}),
      );
    });

    // -- ext.flutterpilot.stopRecording ---------------------------------------
    registerExtension('ext.flutterpilot.stopRecording', (
      method,
      parameters,
    ) async {
      FlutterPilot._isRecording = false;
      return ServiceExtensionResponse.result(
        json.encode({'actions': FlutterPilot._recordedActions}),
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
  }
}
