part of '../../flutterpilot_sdk.dart';

/// Diagnostics and inspection service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `getSummary` — High-level app snapshot
/// - `ping` — Health-check endpoint
/// - `getCapabilities` — Registered SDK/plugin capability metadata
/// - `getErrors` — Buffered error list
/// - `getSemanticsTree` — Accessibility semantics tree
/// - `captureScreenshot` — Base64-encoded PNG screenshot
/// - `clearDebugLogs` — Clear the console capture buffer
/// - `pumpFrames` — Wait for N animation frames
/// - `profiling` — Quiet the AI overlay during a profile; frame budget
/// The AI overlay setting while profile_action has it off.
bool? _overlayBeforeProfiling;

/// Kept alive once get_semantics_tree is first used.
SemanticsHandle? _semanticsHandle;

/// One node of get_semantics_tree's answer, with its children down to
/// [maxDepth].
@visibleForTesting
Map<String, dynamic> debugSemanticsNodeToMap(
  SemanticsNode node, {
  int maxDepth = 50,
  int depth = 0,
}) {
  final children = <Map<String, dynamic>>[];
  if (depth < maxDepth) {
    node.visitChildren((child) {
      children.add(
        debugSemanticsNodeToMap(child, maxDepth: maxDepth, depth: depth + 1),
      );
      return true;
    });
  }
  // ignore: deprecated_member_use
  bool f(SemanticsFlag flag) => node.hasFlag(flag);
  // Only what is set: most nodes have no text and no flags, and nine
  // `false`s per node were most of the response.
  return {
    'id': node.id,
    if (node.label.isNotEmpty) 'label': node.label,
    if (node.value.isNotEmpty) 'value': node.value,
    if (node.hint.isNotEmpty) 'hint': node.hint,
    if (node.tooltip.isNotEmpty) 'tooltip': node.tooltip,
    if (f(SemanticsFlag.isButton)) 'isButton': true,
    if (f(SemanticsFlag.isTextField)) 'isTextField': true,
    if (f(SemanticsFlag.hasCheckedState))
      'isChecked': f(SemanticsFlag.isChecked),
    if (f(SemanticsFlag.hasEnabledState) && !f(SemanticsFlag.isEnabled))
      'isEnabled': false,
    if (f(SemanticsFlag.isFocused)) 'isFocused': true,
    if (f(SemanticsFlag.isImage)) 'isImage': true,
    if (f(SemanticsFlag.isSlider)) 'isSlider': true,
    if (f(SemanticsFlag.isLink)) 'isLink': true,
    if (f(SemanticsFlag.isLiveRegion)) 'isLiveRegion': true,
    'rect': {
      'l': node.rect.left.toStringAsFixed(1),
      't': node.rect.top.toStringAsFixed(1),
      'r': node.rect.right.toStringAsFixed(1),
      'b': node.rect.bottom.toStringAsFixed(1),
    },
    if (children.isNotEmpty) 'children': children,
  };
}

extension _DiagnosticsExtensions on FlutterPilot {
  static void register() {
    // -- ext.flutterpilot.getAppSnapshot --------------------------------------
    registerExtension('ext.flutterpilot.getAppSnapshot', (
      method,
      parameters,
    ) async {
      final snapshot = FlutterPilot.getAppSnapshot();
      return ServiceExtensionResponse.result(json.encode(snapshot));
    });

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
          'isRecording': TestRecorder.active,
          'widgetCount': root != null
              ? PilotWidgetInspector.countElements(root)
              : 0,
        }),
      );
    });

    // -- ext.flutterpilot.ping ------------------------------------------------
    registerExtension('ext.flutterpilot.ping', (method, parameters) async {
      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'ok',
          'version': '0.0.1',
          // Native (idb) coordinates are points: physical pixels / this.
          'devicePixelRatio': WidgetsBinding
              .instance
              .platformDispatcher
              .views
              .firstOrNull
              ?.devicePixelRatio,
        }),
      );
    });

    // -- ext.flutterpilot.getCapabilities ------------------------------------
    registerExtension('ext.flutterpilot.getCapabilities', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({
          'protocolVersion': '1',
          'capabilities': FlutterPilot.capabilities,
        }),
      );
    });

    // -- ext.flutterpilot.getErrors -------------------------------------------
    registerExtension('ext.flutterpilot.getErrors', (method, parameters) async {
      return ServiceExtensionResponse.result(
        json.encode({'errors': ErrorInspector.errors}),
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

      // Flutter only builds semantics while an accessibility client asks for
      // them (none on desktop / without a screen reader). Turn them on once.
      if (_semanticsHandle == null) {
        _semanticsHandle = SemanticsBinding.instance.ensureSemantics();
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
      }
      SemanticsNode? root;
      try {
        // Semantics live on each view's PipelineOwner, not the root one.
        for (final view in RendererBinding.instance.renderViews) {
          root ??= view.owner?.semanticsOwner?.rootSemanticsNode;
        }
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
        json.encode({
          'tree': debugSemanticsNodeToMap(root, maxDepth: maxDepth),
        }),
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

    // -- ext.flutterpilot.clearDebugLogs --------------------------------------
    registerExtension('ext.flutterpilot.clearDebugLogs', (
      method,
      parameters,
    ) async {
      FlutterPilot._clearConsoleBuffer();
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

    // -- ext.flutterpilot.profiling -------------------------------------------
    // profile_action brackets its window with enabled:true/false: the AI tap
    // overlay animates on every frame, and its rebuilds are not the app's.
    registerExtension('ext.flutterpilot.profiling', (method, parameters) async {
      if (parameters['enabled'] == 'true') {
        _overlayBeforeProfiling ??= AiOverlayManager.enabled;
        AiOverlayManager.enabled = false;
        AiOverlayManager.clearNow();
      } else if (_overlayBeforeProfiling != null) {
        AiOverlayManager.enabled = _overlayBeforeProfiling!;
        _overlayBeforeProfiling = null;
      }
      return ServiceExtensionResponse.result(
        json.encode({
          'frameBudgetMs': FrameBudgetProfiler.frameBudgetMs,
          'appVisible': FrameBudgetProfiler.appVisible,
        }),
      );
    });
  }
}
