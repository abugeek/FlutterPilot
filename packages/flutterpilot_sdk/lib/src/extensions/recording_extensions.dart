part of '../../flutterpilot_sdk.dart';

/// Recording and custom tool service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `testRecording` — Record actions and assertions for a generated test
/// - `listCustomTools` — List registered custom tools
/// - `callCustomTool` — Invoke a custom tool by name
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

    // -- ext.flutterpilot.prepareRestart --------------------------------------
    // Data for after the hot restart the server is about to do (a
    // scenario's mocks), read by FlutterPilot.takeRestartData.
    registerExtension('ext.flutterpilot.prepareRestart', (
      method,
      parameters,
    ) async {
      try {
        RestartStore.save(
          (json.decode(parameters['data'] ?? '{}') as Map)
              .cast<String, dynamic>(),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Could not keep data across the restart: $e',
        );
      }
      return ServiceExtensionResponse.result(json.encode({'saved': true}));
    });

    // -- ext.flutterpilot.platformChannel -------------------------------------
    // action=mock: answer the app's calls to channel (+ method) with result
    // (JSON) or errorCode; emit: deliver event (JSON) to the channel's
    // EventChannel listeners; clear: drop mocks. Always returns the active
    // mocks and the calls the app made.
    registerExtension('ext.flutterpilot.platformChannel', (
      method,
      parameters,
    ) async {
      final channel = parameters['channel'];
      final name = parameters['method'];
      final code = parameters['errorCode'];
      Object? decoded(String key) =>
          parameters[key] == null ? null : json.decode(parameters[key]!);
      bool? listening;
      var cleared = 0;
      try {
        switch (parameters['action']) {
          case 'mock':
            PlatformChannelMocks.mock(
              channel!,
              method: name,
              result: decoded('result'),
              errorCode: code,
              errorMessage: parameters['errorMessage'],
            );
          case 'emit':
            listening = PlatformChannelMocks.emit(
              channel!,
              decoded('event'),
              errorCode: code,
              errorMessage: parameters['errorMessage'],
            );
          case 'clear':
            cleared = PlatformChannelMocks.clear(
              channel: channel,
              method: name,
            );
        }
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          '$e',
        );
      }
      return ServiceExtensionResponse.result(
        json.encode({
          'installed': PlatformChannelMocks.installed,
          'mocks': PlatformChannelMocks.mocks,
          'calls': PlatformChannelMocks.calls,
          'listeners': PlatformChannelMocks.listeners,
          'listening': ?listening,
          'cleared': cleared,
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
  }
}
