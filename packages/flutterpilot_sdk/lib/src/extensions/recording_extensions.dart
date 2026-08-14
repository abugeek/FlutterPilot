part of '../../flutterpilot_sdk.dart';

/// Recording and custom tool service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `startRecording` — Begin recording user interactions
/// - `stopRecording` — Stop recording and return captured actions
/// - `listCustomTools` — List registered custom tools
/// - `callCustomTool` — Invoke a custom tool by name
/// - `getFlightLog` — Read full timeline from continuous FlightRecorder
/// - `generateReproTest` — Synthesize executable repro_test.dart test code
/// - `exportTestSuite` — Synthesize Patrol / Integration / Widget test suites
/// - `clearFlightLog` — Reset the flight recorder buffer
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
        json.encode({'actions': FlutterPilot._recordedActions.toList()}),
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

    // -- ext.flutterpilot.generateReproTest -----------------------------------
    registerExtension('ext.flutterpilot.generateReproTest', (
      method,
      parameters,
    ) async {
      final testName = parameters['testName'];
      final initialWidgetName = parameters['widgetName'];
      final code = ReproTestGenerator.generate(
        testName: testName,
        initialWidgetName: initialWidgetName,
      );
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success', 'code': code}),
      );
    });

    // -- ext.flutterpilot.exportTestSuite ------------------------------------
    registerExtension('ext.flutterpilot.exportTestSuite', (
      method,
      parameters,
    ) async {
      final frameworkStr = parameters['framework'] ?? 'patrol';
      final framework = TestFramework.fromString(frameworkStr);
      final testName = parameters['testName'];
      final appWidget = parameters['appWidget'];

      final code = TestSynthesizer.generate(
        framework: framework,
        testName: testName,
        appWidget: appWidget,
      );

      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'success',
          'framework': framework.name,
          'code': code,
        }),
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

    // -- ext.flutterpilot.replayFlightLog ------------------------------------
    registerExtension('ext.flutterpilot.replayFlightLog', (
      method,
      parameters,
    ) async {
      final speedMs = int.tryParse(parameters['delayMs'] ?? '150') ?? 150;
      final events = FlightRecorder.getSnapshotEvents();
      int replayedCount = 0;

      for (final event in events) {
        final data = event.data;
        if (event.category == 'gesture' && event.action == 'tapAt') {
          final x = (data['x'] as num?)?.toDouble();
          final y = (data['y'] as num?)?.toDouble();
          if (x != null && y != null) {
            await InteractionManager.tapAt(Offset(x, y));
            replayedCount++;
            await Future.delayed(Duration(milliseconds: speedMs));
          }
        } else if (event.category == 'action' && event.action == 'tapWidget') {
          final key = data['key']?.toString();
          if (key != null) {
            final el = PilotWidgetInspector.findElement(key);
            if (el != null && el.renderObject is RenderBox) {
              final ro = el.renderObject as RenderBox;
              final pos = ro.localToGlobal(ro.size.center(Offset.zero));
              await InteractionManager.tapAt(pos, label: key);
              replayedCount++;
              await Future.delayed(Duration(milliseconds: speedMs));
            }
          }
        }
      }

      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'replayed',
          'replayedEventsCount': replayedCount,
          'totalEventsInFlight': events.length,
        }),
      );
    });
  }
}
