import 'dart:convert';
import 'dart:developer';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Checkbox, Radio, Slider, Switch;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/chaos_fuzzer.dart';
import 'src/error_inspector.dart';
import 'src/flight_recorder.dart';
import 'src/interaction_manager.dart';
import 'src/memory_auditor.dart';
import 'src/navigation_tracker.dart';
import 'src/repro_test_generator.dart';
import 'src/ring_buffer.dart';
import 'src/state_snapshot_manager.dart';
import 'src/frame_budget_profiler.dart';
import 'src/stream_inspector.dart';
import 'src/test_synthesizer.dart';
import 'src/ui_health_auditor.dart';
import 'src/widget_inspector.dart';

export 'src/chaos_fuzzer.dart';
export 'src/error_inspector.dart';
export 'src/fixture_manager.dart';
export 'src/flight_recorder.dart';
export 'src/frame_budget_profiler.dart';
export 'src/gif_encoder.dart';
export 'src/interaction_manager.dart';
export 'src/memory_auditor.dart';
export 'src/navigation_tracker.dart';
export 'src/pr_report_generator.dart';
export 'src/repro_test_generator.dart';
export 'src/ring_buffer.dart';
export 'src/state_snapshot_manager.dart';
export 'src/stream_inspector.dart';
export 'src/test_synthesizer.dart';
export 'src/ui_health_auditor.dart';
export 'src/widget_inspector.dart';

part 'src/extensions/widget_extensions.dart';
part 'src/extensions/navigation_extensions.dart';
part 'src/extensions/state_extensions.dart';
part 'src/extensions/diagnostics_extensions.dart';
part 'src/extensions/recording_extensions.dart';

/// The core class for the FlutterPilot SDK — an AI-native runtime
/// introspection toolkit for Flutter applications.
///
/// FlutterPilot exposes Dart VM [service extensions] that allow external
/// tools (AI agents, IDEs, CLI) to inspect widget trees, capture
/// screenshots, simulate user interactions, manage navigation, record
/// sessions, and more — all at runtime over the VM service protocol.
///
/// ## Quick start
///
/// ```dart
/// void main() {
///   FlutterPilot.initialize();
///   runApp(const MyApp());
/// }
/// ```
///
/// Add the [NavigationTracker] observer to enable route tracking:
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [NavigationTracker()],
/// )
/// ```
///
/// **Important:** This SDK relies on Dart service extensions and should
/// only be included in **debug / profile** builds. It is a no-op when
/// called after the first [initialize] invocation.
///
/// ## Service extensions
///
/// All registered extensions use the `ext.flutterpilot.*` namespace.
/// See the individual extension registrations inside
/// [_registerServiceExtensions] for the full protocol reference.
///
/// ## Extending FlutterPilot
///
/// * Register custom tools with [registerCustomTool].
/// * Register state-management setters with [registerStateSetter].
class FlutterPilot {
  FlutterPilot._();

  static bool _initialized = false;

  /// Whether the SDK has been initialized via [initialize].
  ///
  /// Plugins should check this before registering service extensions to ensure
  /// the core SDK is ready.
  static bool get isInitialized => _initialized;

  /// Registers machine-readable metadata for an SDK integration/plugin.
  ///
  /// Plugins should call this once during registration so agents can discover
  /// the exact extension surface without relying on hard-coded tool lists.
  static void registerCapability(
    String id, {
    required String version,
    required List<String> extensions,
    bool mutating = false,
  }) {
    _capabilities[id] = {
      'id': id,
      'version': version,
      'extensions': List<String>.unmodifiable(extensions),
      'mutating': mutating,
    };
  }

  /// Returns a snapshot of registered integration capabilities.
  static List<Map<String, dynamic>> get capabilities => _capabilities.values
      .map((value) => Map<String, dynamic>.from(value))
      .toList();

  static final Map<String, Function> _customTools = {};
  static final Map<String, Map<String, dynamic>> _capabilities = {};
  static final Map<String, Future<dynamic> Function(String name, dynamic value)>
  _stateSetters = {};
  static final Map<String, String? Function(String name)> _stateReaders = {};
  static bool _isRecording = false;
  static const int _maxRecordedActions = 5000;
  static final RingBuffer<Map<String, dynamic>> _recordedActions = RingBuffer(
    _maxRecordedActions,
  );
  // Held to keep the semantics tree alive once enabled.
  static SemanticsHandle? _semanticsHandle;

  /// A [ValueNotifier] that broadcasts locale overrides to the widget tree.
  ///
  /// When a non-null [ui.Locale] is set via the `ext.flutterpilot.setLocale`
  /// service extension, widgets listening to this notifier can rebuild with
  /// the new locale. Setting the value back to `null` restores the
  /// platform default.
  ///
  /// ```dart
  /// ValueListenableBuilder<Locale?>(
  ///   valueListenable: FlutterPilot.localeNotifier,
  ///   builder: (context, locale, child) {
  ///     // Use locale override or fall back to platform locale.
  ///     return MaterialApp(locale: locale);
  ///   },
  /// )
  /// ```
  static final ValueNotifier<ui.Locale?> localeNotifier = ValueNotifier(null);

  /// A [ValueNotifier] that broadcasts text-scale overrides.
  ///
  /// Wrap your `MaterialApp` (or any widget) with a [MediaQuery] that reads
  /// this notifier to support accessibility testing via `set_text_scale_factor`:
  ///
  /// ```dart
  /// ValueListenableBuilder<double?>(
  ///   valueListenable: FlutterPilot.textScaleNotifier,
  ///   builder: (ctx, scale, child) {
  ///     return MediaQuery(
  ///       data: MediaQuery.of(ctx).copyWith(
  ///         textScaler: scale != null
  ///             ? TextScaler.linear(scale)
  ///             : MediaQuery.of(ctx).textScaler,
  ///       ),
  ///       child: child!,
  ///     );
  ///   },
  ///   child: MaterialApp(...),
  /// )
  /// ```
  static final ValueNotifier<double?> textScaleNotifier = ValueNotifier(null);

  static double _lastFps = 0;
  static int _frameCount = 0;
  static DateTime _lastFpsUpdate = DateTime.now();

  static int _screenMutationCount = 0;

  /// Current 64-bit frame mutation counter.
  static int get screenMutationCount => _screenMutationCount;

  /// Signals that the screen UI or state has mutated.
  static void notifyMutation() {
    _screenMutationCount++;
    PilotWidgetInspector.invalidateCache();
  }

  // -- Debug console capture -------------------------------------------------
  static DebugPrintCallback? _originalDebugPrint;
  static const int _consoleBufferMax = 500;
  static const int _consoleBufferMaxBytes = 1024 * 1024;
  static final RingBuffer<Map<String, dynamic>> _consoleBuffer = RingBuffer(
    _consoleBufferMax,
  );
  static int _consoleBufferBytes = 0;

  /// Returns a copy of the captured console log buffer (up to 500 entries).
  /// Each entry has keys: `timestamp`, `level`, `logger`, `message`.
  static List<Map<String, dynamic>> get consoleBuffer =>
      List.unmodifiable(_consoleBuffer.toList());

  /// Initializes the FlutterPilot SDK.
  ///
  /// This is the main entry point and **must be called before `runApp`**.
  /// It wires up internal modules ([ErrorInspector], [NavigationTracker],
  /// [InteractionManager]), registers all `ext.flutterpilot.*` service
  /// extensions, and starts the FPS counter.
  ///
  /// Calling [initialize] more than once is safe — subsequent calls are
  /// silently ignored.
  ///
  /// ```dart
  /// void main() {
  ///   FlutterPilot.initialize();
  ///   runApp(const MyApp());
  /// }
  /// ```
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _setupModules();
    _registerServiceExtensions();
    _setupFpsCounter();
    _setupDebugPrintCapture();
    FrameBudgetProfiler.initialize();
    debugPrint('FlutterPilot initialized 🚀');
  }

  static void _setupModules() {
    // Navigation
    NavigationTracker.onStateChange = (source, name, value) {
      FlightRecorder.recordRoute(name, {
        'source': source,
        'value': _safeJsonEncode(value),
      });
      logStateChange(source, name, value);
    };

    // Errors
    ErrorInspector.initialize();
    ErrorInspector.onErrorCaptured = (details) {
      FlightRecorder.recordError(
        details.exceptionAsString(),
        details.stack?.toString(),
      );
      if (_isRecording) {
        _recordAction('error', {'exception': details.exceptionAsString()});
      }
      postEvent('ext.flutterpilot.error', {
        'exception': details.exceptionAsString(),
      });
    };

    // Interactions
    InteractionManager.initialize();
    InteractionManager.onPointerDown = (info) {
      FlightRecorder.recordGesture('tapAt', info);
      if (_isRecording) {
        _recordAction('user_tap', info);
      }
    };
  }

  static bool _fpsCounterRunning = false;

  static void _setupFpsCounter() {
    if (_fpsCounterRunning) return;
    _fpsCounterRunning = true;
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  static void _onFrame(Duration timestamp) {
    if (!_fpsCounterRunning) return;
    _frameCount++;
    final now = DateTime.now();
    final diff = now.difference(_lastFpsUpdate).inMilliseconds;
    if (diff >= 1000) {
      _lastFps = (_frameCount * 1000) / diff;
      _frameCount = 0;
      _lastFpsUpdate = now;
    }
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  /// Stops the FPS counter and clears internal state.
  ///
  /// Call this during teardown or hot-restart cleanup to prevent
  /// stale frame callbacks from accumulating.
  static void dispose() {
    _fpsCounterRunning = false;
    _frameCount = 0;
    _lastFps = 0;
  }

  // Intercepts debugPrint so that every message is captured in FlutterPilot's
  // internal diagnostic buffer without duplicating console output.
  static void _setupDebugPrintCapture() {
    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      final line = message ?? '';
      _originalDebugPrint!(line, wrapWidth: wrapWidth);
      _captureConsoleLine(line, level: 'info', logger: 'debugPrint');
    };
  }

  static void _captureConsoleLine(
    String message, {
    String level = 'info',
    String logger = '',
  }) {
    final safeMessage = _redactDiagnosticText(message);
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'level': level,
      'logger': logger,
      'message': safeMessage,
    };
    _consoleBufferBytes += utf8.encode(jsonEncode(entry)).length;
    _consoleBuffer.add(entry);
    while (_consoleBufferBytes > _consoleBufferMaxBytes &&
        _consoleBuffer.isNotEmpty) {
      final removed = _consoleBuffer.removeFirst();
      _consoleBufferBytes -= utf8.encode(jsonEncode(removed)).length;
    }
  }

  static void _clearConsoleBuffer() {
    _consoleBuffer.clear();
    _consoleBufferBytes = 0;
  }

  /// Registers a custom tool that can be invoked remotely via the
  /// `ext.flutterpilot.callCustomTool` service extension.
  ///
  /// [name] is the unique identifier used to call the tool.
  /// [callback] receives the service-extension parameters map and may
  /// return a JSON-encodable result.
  ///
  /// ```dart
  /// FlutterPilot.registerCustomTool('resetOnboarding', (params) async {
  ///   await prefs.setBool('onboarded', false);
  ///   return {'cleared': true};
  /// });
  /// ```
  ///
  /// Registered tools are listed by `ext.flutterpilot.listCustomTools`.
  static void registerCustomTool(String name, Function callback) {
    _customTools[name] = callback;
  }

  /// Registers a state setter for a specific state-management [type].
  ///
  /// The setter is invoked by the `ext.flutterpilot.setState` service
  /// extension. [type] identifies the state-management system (e.g.,
  /// `'riverpod'`, `'bloc'`, `'provider'`). [setter] receives a state
  /// [name] and a decoded JSON [value], and should apply the state change.
  ///
  /// ```dart
  /// FlutterPilot.registerStateSetter('riverpod', (name, value) async {
  ///   final provider = lookupProviderByName(name);
  ///   container.read(provider.notifier).state = value;
  ///   return container.read(provider);
  /// });
  /// ```
  static void registerStateSetter(
    String type,
    Future<dynamic> Function(String name, dynamic value) setter,
  ) {
    _stateSetters[type] = setter;
  }

  /// Registers a state reader for a state-management type (e.g. `'riverpod'`,
  /// `'bloc'`). The [reader] receives a state [name] and returns the current
  /// value as a string, or null if not found.
  ///
  /// Used by `ext.flutterpilot.waitForState` to poll state without coupling
  /// the core SDK to any specific state-management library.
  ///
  /// ```dart
  /// FlutterPilot.registerStateReader('riverpod', (name) {
  ///   return RiverpodPilotObserver.currentValueString(name);
  /// });
  /// ```
  static void registerStateReader(
    String type,
    String? Function(String name) reader,
  ) {
    _stateReaders[type] = reader;
  }

  /// Logs a state change event when session recording is active.
  ///
  /// Called internally by [NavigationTracker] and can also be called
  /// directly from application code to log custom state transitions.
  ///
  /// [source] identifies the origin (e.g., `'navigation'`, `'riverpod'`).
  /// [name] is the event name (e.g., `'push'`). [value] is the payload.
  static void logStateChange(String source, String name, dynamic value) {
    if (_isRecording) {
      _recordAction('state_change', {
        'source': source,
        'name': name,
        'value': _safeJsonEncode(value),
      });
    }
  }

  static void _recordAction(String type, Map<String, dynamic> data) {
    if (!_isRecording) return;
    _recordedActions.add({
      'type': type,
      'timestamp': DateTime.now().toIso8601String(),
      'data': data,
    });
    postEvent('ext.flutterpilot.action', {'type': type, 'data': data});
  }

  // ---------------------------------------------------------------------------
  // Service extensions
  //
  // Each extension is registered under the `ext.flutterpilot.*` namespace and
  // can be called via the Dart VM service protocol (e.g., from DevTools, the
  // FlutterPilot CLI, or any JSON-RPC client connected to the VM service).
  //
  // Parameters are passed as `Map<String, String>` — numeric values should be
  // sent as string representations and are parsed internally.
  // ---------------------------------------------------------------------------

  static void _registerServiceExtensions() {
    // tapAt stays in the main file as it is a simple coordinate-based action
    // that doesn't fit neatly into any extension group.
    registerExtension('ext.flutterpilot.tapAt', (method, parameters) async {
      final x = double.tryParse(parameters['x'] ?? '');
      final y = double.tryParse(parameters['y'] ?? '');
      if (x == null || y == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Invalid coords',
        );
      }
      if (_isRecording) _recordAction('tapAt', {'x': x, 'y': y});
      await InteractionManager.tapAt(Offset(x, y));
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // Register extension groups from part files.
    _WidgetExtensions.register();
    _NavigationExtensions.register();
    _StateExtensions.register();
    _DiagnosticsExtensions.register();
    _RecordingExtensions.register();
  }

  /// Shared helper for assertWidgetEnabled / assertWidgetDisabled to
  /// eliminate code duplication.
  static ServiceExtensionResponse _assertWidgetState(
    Element element,
    String key, {
    required bool shouldBeEnabled,
  }) {
    final props = <String, dynamic>{};
    _extractWidgetProps(element, props);
    final isEnabled = props['isEnabled'] as bool? ?? true;
    if (isEnabled != shouldBeEnabled) {
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        json.encode({
          'error':
              'Widget "$key" is ${isEnabled ? 'enabled' : 'disabled'}, '
              'expected ${shouldBeEnabled ? 'enabled' : 'disabled'}.',
        }),
      );
    }
    return ServiceExtensionResponse.result(
      json.encode({'status': 'passed', 'key': key, 'isEnabled': isEnabled}),
    );
  }

  /// Extracts semantic properties from [element] into [props].
  ///
  /// Reads widget-type-specific properties via dynamic dispatch:
  /// - [Text.data] → `text`
  /// - [EditableTextState.controller.text] → `text`, `isFocused`
  /// - [Checkbox.value] / [Switch.value] → `isChecked`
  /// - [Slider.value] / [Slider.min] / [Slider.max] → `value`, `min`, `max`
  /// - `onPressed` / `onTap` / `onChanged` → `isEnabled`
  /// - [RenderBox] global bounds → `bounds`
  static void _extractWidgetProps(Element element, Map<String, dynamic> props) {
    final widget = element.widget;
    final dyn = widget as dynamic;

    // Direct text content (Text widget)
    try {
      final t = dyn.data;
      if (t is String) props['text'] = t;
    } catch (_) {}

    // Enabled/disabled via common callback names
    try {
      props['isEnabled'] = (dyn.onPressed as Object?) != null;
    } catch (_) {}
    if (!props.containsKey('isEnabled')) {
      try {
        props['isEnabled'] = (dyn.onTap as Object?) != null;
      } catch (_) {}
    }
    // Checkbox / Switch — use onChanged for enabled check and value for state
    try {
      final v = dyn.value;
      if (v is bool) props['isChecked'] = v;
      if (!props.containsKey('isEnabled')) {
        props['isEnabled'] = (dyn.onChanged as Object?) != null;
      }
    } catch (_) {}

    // Slider
    try {
      final v = dyn.value;
      if (v is double) {
        props['value'] = v;
        props['isEnabled'] = (dyn.onChanged as Object?) != null;
      }
    } catch (_) {}
    try {
      final mn = dyn.min;
      if (mn is double) props['min'] = mn;
    } catch (_) {}
    try {
      final mx = dyn.max;
      if (mx is double) props['max'] = mx;
    } catch (_) {}

    // EditableText — current controller text and focus state
    bool foundEditable = false;
    void visitForEditable(Element e) {
      if (foundEditable) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        try {
          final state = e.state as EditableTextState;
          props['text'] = state.widget.controller.text;
          props['isFocused'] = state.widget.focusNode.hasFocus;
          if (!props.containsKey('isEnabled')) props['isEnabled'] = true;
          foundEditable = true;
        } catch (_) {}
        return;
      }
      e.visitChildren(visitForEditable);
    }

    visitForEditable(element);

    // Focus state fallback
    if (!props.containsKey('isFocused')) {
      props['isFocused'] =
          FocusManager.instance.primaryFocus?.context == element;
    }

    // Screen-space bounding box
    final renderObject = element.renderObject;
    if (renderObject is RenderBox && renderObject.hasSize) {
      final offset = renderObject.localToGlobal(Offset.zero);
      props['bounds'] = {
        'x': offset.dx.toStringAsFixed(1),
        'y': offset.dy.toStringAsFixed(1),
        'width': renderObject.size.width.toStringAsFixed(1),
        'height': renderObject.size.height.toStringAsFixed(1),
      };
    }
  }

  static const int _maxDiagnosticStringLength = 10000;
  static const int _maxDiagnosticCollectionItems = 500;
  static final RegExp _sensitiveKey = RegExp(
    r'(password|passwd|secret|token|api[_-]?key|authorization|cookie|private[_-]?key|client[_-]?secret)',
    caseSensitive: false,
  );

  static String _redactDiagnosticText(String value) {
    if (value.length > _maxDiagnosticStringLength) {
      value = '${value.substring(0, _maxDiagnosticStringLength)}…<truncated>';
    }
    return value.replaceAll(
      RegExp(r'(Bearer\s+)[A-Za-z0-9._~-]+', caseSensitive: false),
      r'${1}<redacted>',
    );
  }

  static dynamic _safeJsonEncode(dynamic object, [int depth = 0, String? key]) {
    if (depth > 10) return '<max depth exceeded>';
    if (key != null && _sensitiveKey.hasMatch(key)) return '<redacted>';
    if (object == null || object is num || object is bool || object is String) {
      return object is String ? _redactDiagnosticText(object) : object;
    }
    if (object is Map) {
      final entries = object.entries.take(_maxDiagnosticCollectionItems);
      final result = <String, dynamic>{
        for (final entry in entries)
          entry.key.toString(): _safeJsonEncode(
            entry.value,
            depth + 1,
            entry.key.toString(),
          ),
      };
      if (object.length > _maxDiagnosticCollectionItems) {
        result['<truncated>'] = object.length - _maxDiagnosticCollectionItems;
      }
      return result;
    }
    if (object is Iterable) {
      final values = object
          .take(_maxDiagnosticCollectionItems)
          .map((e) => _safeJsonEncode(e, depth + 1))
          .toList();
      if (object.length > _maxDiagnosticCollectionItems) {
        values.add(
          '<truncated: ${object.length - _maxDiagnosticCollectionItems} items>',
        );
      }
      return values;
    }
    try {
      return _safeJsonEncode((object as dynamic).toJson(), depth + 1, key);
    } on NoSuchMethodError catch (_) {
      return _redactDiagnosticText(object.toString());
    }
  }

  static Future<Uint8List?> _captureScreenshot({double scale = 1.0}) async {
    try {
      final basePixelRatio =
          WidgetsBinding
              .instance
              .platformDispatcher
              .implicitView
              ?.devicePixelRatio ??
          1.0;
      final targetPixelRatio = (basePixelRatio * scale).clamp(
        0.2,
        basePixelRatio,
      );
      RenderRepaintBoundary? boundary;
      void findBoundary(RenderObject object) {
        if (boundary != null) return;
        if (object is RenderRepaintBoundary) {
          boundary = object;
          return;
        }
        object.visitChildren(findBoundary);
      }

      for (final rv in WidgetsBinding.instance.renderViews) {
        findBoundary(rv);
      }
      if (boundary != null) {
        final image = await boundary!.toImage(pixelRatio: targetPixelRatio);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Screenshot error: $e');
    }
    return null;
  }
}
