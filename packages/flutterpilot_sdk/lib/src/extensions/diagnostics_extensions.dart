part of '../../flutterpilot_sdk.dart';

/// Diagnostics and inspection service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `getSummary` — High-level app snapshot
/// - `ping` — Health-check endpoint
/// - `getErrors` — Buffered error list
/// - `getPerfMetrics` — FPS estimate
/// - `getSemanticsTree` — Accessibility semantics tree
/// - `captureScreenshot` — Base64-encoded PNG screenshot
/// - `getDebugLogs` — In-memory console capture buffer
/// - `clearDebugLogs` — Clear the console capture buffer
/// - `pumpFrames` — Wait for N animation frames
extension _DiagnosticsExtensions on FlutterPilot {
  static void register() {
    // -- ext.flutterpilot.getSummary ------------------------------------------
    registerExtension('ext.flutterpilot.getSummary', (
      method,
      parameters,
    ) async {
      final root = WidgetsBinding.instance.rootElement;
      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'ok',
          'currentRoute': NavigationTracker.currentRoute,
          'errorCount': ErrorInspector.errors.length,
          'isRecording': FlutterPilot._isRecording,
          'widgetCount': root != null
              ? PilotWidgetInspector.countElements(root)
              : 0,
        }),
      );
    });

    // -- ext.flutterpilot.ping ------------------------------------------------
    registerExtension('ext.flutterpilot.ping', (method, parameters) async {
      return ServiceExtensionResponse.result(
        json.encode({'status': 'ok', 'version': '0.0.1'}),
      );
    });

    // -- ext.flutterpilot.getErrors -------------------------------------------
    registerExtension('ext.flutterpilot.getErrors', (method, parameters) async {
      return ServiceExtensionResponse.result(
        json.encode({'errors': ErrorInspector.errors}),
      );
    });

    // -- ext.flutterpilot.getPerfMetrics --------------------------------------
    registerExtension('ext.flutterpilot.getPerfMetrics', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({
          'fps': FlutterPilot._lastFps.toStringAsFixed(1),
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    });

    // -- ext.flutterpilot.getSemanticsTree ------------------------------------
    registerExtension('ext.flutterpilot.getSemanticsTree', (
      method,
      parameters,
    ) async {
      FlutterPilot._semanticsHandle ??= SemanticsBinding.instance
          .ensureSemantics();
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;

      final maxDepth = int.tryParse(parameters['maxDepth'] ?? '') ?? 50;

      Map<String, dynamic> nodeToMap(SemanticsNode node, int depth) {
        final children = <Map<String, dynamic>>[];
        if (depth < maxDepth) {
          node.visitChildren((child) {
            children.add(nodeToMap(child, depth + 1));
            return true;
          });
        }
        // ignore: unused_local_variable
        final flags = node.flagsCollection;
        // ignore: deprecated_member_use
        bool f(SemanticsFlag flag) => node.hasFlag(flag);
        return {
          'id': node.id,
          'label': node.label.isEmpty ? null : node.label,
          'value': node.value.isEmpty ? null : node.value,
          'hint': node.hint.isEmpty ? null : node.hint,
          'tooltip': node.tooltip.isEmpty ? null : node.tooltip,
          'isButton': f(SemanticsFlag.isButton),
          'isTextField': f(SemanticsFlag.isTextField),
          'isChecked': f(SemanticsFlag.isChecked),
          'isEnabled':
              !f(SemanticsFlag.hasEnabledState) || f(SemanticsFlag.isEnabled),
          'isFocused': f(SemanticsFlag.isFocused),
          'isImage': f(SemanticsFlag.isImage),
          'isSlider': f(SemanticsFlag.isSlider),
          'isLink': f(SemanticsFlag.isLink),
          'isLiveRegion': f(SemanticsFlag.isLiveRegion),
          'rect': {
            'l': node.rect.left.toStringAsFixed(1),
            't': node.rect.top.toStringAsFixed(1),
            'r': node.rect.right.toStringAsFixed(1),
            'b': node.rect.bottom.toStringAsFixed(1),
          },
          if (children.isNotEmpty) 'children': children,
        };
      }

      SemanticsNode? root;
      try {
        root = RendererBinding
            .instance
            .rootPipelineOwner
            .semanticsOwner
            ?.rootSemanticsNode;
      } catch (_) {
        // rootPipelineOwner is an internal Flutter API — may not be available
        // in all Flutter versions. Fall back gracefully.
      }
      if (root == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Semantics tree not yet available — try again after one more frame',
        );
      }
      return ServiceExtensionResponse.result(
        json.encode({'tree': nodeToMap(root, 0)}),
      );
    });

    // -- ext.flutterpilot.captureScreenshot -----------------------------------
    registerExtension('ext.flutterpilot.captureScreenshot', (
      method,
      parameters,
    ) async {
      try {
        final scale = double.tryParse(parameters['scale'] ?? '') ?? 1.0;
        final bytes = await FlutterPilot._captureScreenshot(scale: scale);
        if (bytes == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'No RenderView',
          );
        }
        return ServiceExtensionResponse.result(
          json.encode({'data': base64Encode(bytes)}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Error: $e',
        );
      }
    });

    // -- ext.flutterpilot.getDebugLogs ----------------------------------------
    registerExtension('ext.flutterpilot.getDebugLogs', (
      method,
      parameters,
    ) async {
      final levelFilter = parameters['level'];
      final limit = int.tryParse(parameters['limit'] ?? '') ?? 100;
      var entries = FlutterPilot._consoleBuffer.toList();
      if (levelFilter != null && levelFilter.isNotEmpty) {
        entries = entries.where((e) => e['level'] == levelFilter).toList();
      }
      if (entries.length > limit) {
        entries = entries.sublist(entries.length - limit);
      }
      return ServiceExtensionResponse.result(
        json.encode({
          'logs': entries,
          'total': FlutterPilot._consoleBuffer.length,
        }),
      );
    });

    // -- ext.flutterpilot.clearDebugLogs --------------------------------------
    registerExtension('ext.flutterpilot.clearDebugLogs', (
      method,
      parameters,
    ) async {
      FlutterPilot._consoleBuffer.clear();
      return ServiceExtensionResponse.result(json.encode({'cleared': true}));
    });

    // -- ext.flutterpilot.pumpFrames ------------------------------------------
    registerExtension('ext.flutterpilot.pumpFrames', (
      method,
      parameters,
    ) async {
      final count = int.tryParse(parameters['count'] ?? '1') ?? 1;
      for (var i = 0; i < count.clamp(1, 120); i++) {
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
      }
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success', 'frames': count}),
      );
    });

    // -- ext.flutterpilot.getFrameBudgetProfile ------------------------------
    registerExtension('ext.flutterpilot.getFrameBudgetProfile', (
      method,
      parameters,
    ) async {
      final profile = FrameBudgetProfiler.getProfile();
      return ServiceExtensionResponse.result(json.encode(profile));
    });

    // -- ext.flutterpilot.auditUiHealth ---------------------------------------
    registerExtension('ext.flutterpilot.auditUiHealth', (
      method,
      parameters,
    ) async {
      final health = UiHealthAuditor.audit();
      return ServiceExtensionResponse.result(json.encode(health));
    });

    // -- ext.flutterpilot.getStreamLogs ---------------------------------------
    registerExtension('ext.flutterpilot.getStreamLogs', (
      method,
      parameters,
    ) async {
      final channel = parameters['channel'];
      final logs = StreamInspector.getEvents(channelFilter: channel);
      return ServiceExtensionResponse.result(
        json.encode({'logs': logs, 'count': logs.length}),
      );
    });

    // -- ext.flutterpilot.clearStreamLogs -------------------------------------
    registerExtension('ext.flutterpilot.clearStreamLogs', (
      method,
      parameters,
    ) async {
      StreamInspector.clear();
      return ServiceExtensionResponse.result(json.encode({'cleared': true}));
    });
  }
}
