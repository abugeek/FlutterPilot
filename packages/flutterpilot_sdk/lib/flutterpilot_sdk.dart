import 'dart:convert';
import 'dart:developer';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'src/error_inspector.dart';
import 'src/interaction_manager.dart';
import 'src/navigation_tracker.dart';
import 'src/widget_inspector.dart';

export 'src/error_inspector.dart';
export 'src/interaction_manager.dart';
export 'src/navigation_tracker.dart';
export 'src/widget_inspector.dart';

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

  static final Map<String, Function> _customTools = {};
  static final Map<String, Future<dynamic> Function(String name, dynamic value)>
      _stateSetters = {};
  static bool _isRecording = false;
  static final List<Map<String, dynamic>> _recordedActions = [];

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

  static double _lastFps = 0;
  static int _frameCount = 0;
  static DateTime _lastFpsUpdate = DateTime.now();

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
    debugPrint('FlutterPilot initialized 🚀');
  }

  static void _setupModules() {
    // Navigation
    NavigationTracker.onStateChange = (source, name, value) {
      logStateChange(source, name, value);
    };

    // Errors
    ErrorInspector.initialize();
    ErrorInspector.onErrorCaptured = (details) {
      if (_isRecording) {
        _recordAction('error', {'exception': details.exceptionAsString()});
      }
      postEvent('ext.flutterpilot.error', {
        'exception': details.exceptionAsString()
      });
    };

    // Interactions
    InteractionManager.initialize();
    InteractionManager.onPointerDown = (info) {
      if (_isRecording) {
        _recordAction('user_tap', info);
      }
    };
  }

  static void _setupFpsCounter() {
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  static void _onFrame(Duration timestamp) {
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
        'value': _safeJsonEncode(value)
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
    // -- ext.flutterpilot.getSummary ------------------------------------------
    // Returns a high-level snapshot: current route, error count, recording
    // state, and total widget count.
    registerExtension('ext.flutterpilot.getSummary', (method, parameters) async {
      final root = WidgetsBinding.instance.rootElement;
      return ServiceExtensionResponse.result(json.encode({
        'status': 'ok',
        'currentRoute': NavigationTracker.currentRoute,
        'errorCount': ErrorInspector.errors.length,
        'isRecording': _isRecording,
        'widgetCount': root != null ? PilotWidgetInspector.countElements(root) : 0,
      }));
    });

    // -- ext.flutterpilot.ping ------------------------------------------------
    // Health-check endpoint. Returns SDK version.
    registerExtension('ext.flutterpilot.ping', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({
        'status': 'ok', 
        'version': '0.0.1'
      }));
    });

    // -- ext.flutterpilot.getErrors -------------------------------------------
    // Returns the buffered error list from [ErrorInspector].
    registerExtension('ext.flutterpilot.getErrors', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({
        'errors': ErrorInspector.errors
      }));
    });

    // -- ext.flutterpilot.listCustomTools -------------------------------------
    // Lists names of all tools registered via [registerCustomTool].
    registerExtension('ext.flutterpilot.listCustomTools', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({
        'tools': _customTools.keys.toList()
      }));
    });

    // -- ext.flutterpilot.callCustomTool --------------------------------------
    // Invokes a custom tool by `name`. Extra params are forwarded to the
    // callback. Returns `invalidParams` if the tool name is missing or unknown.
    registerExtension('ext.flutterpilot.callCustomTool', (method, parameters) async {
      final name = parameters['name'];
      if (name == null || !_customTools.containsKey(name)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 
          'Tool not found'
        );
      }
      try {
        final result = await _customTools[name]!(parameters);
        return ServiceExtensionResponse.result(json.encode({
          'result': _safeJsonEncode(result)
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, 
          'Error: $e'
        );
      }
    });

    // -- ext.flutterpilot.getWidgetTree ---------------------------------------
    // Captures the full widget tree as a nested JSON structure via
    // [PilotWidgetInspector.captureWidgetTree].
    registerExtension('ext.flutterpilot.getWidgetTree', (method, parameters) async {
      try {
        return ServiceExtensionResponse.result(json.encode({
          'tree': PilotWidgetInspector.captureWidgetTree()
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, 
          'Error: $e'
        );
      }
    });

    // -- ext.flutterpilot.captureScreenshot -----------------------------------
    // Returns a base64-encoded PNG screenshot of the current render tree.
    registerExtension('ext.flutterpilot.captureScreenshot', (method, parameters) async {
      try {
        final bytes = await _captureScreenshot();
        if (bytes == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError, 
            'No RenderView'
          );
        }
        return ServiceExtensionResponse.result(json.encode({
          'data': base64Encode(bytes)
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, 
          'Error: $e'
        );
      }
    });

    // -- ext.flutterpilot.getNavigationStack ----------------------------------
    // Returns the ordered navigation route stack from [NavigationTracker].
    registerExtension('ext.flutterpilot.getNavigationStack', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({
        'stack': NavigationTracker.stack
      }));
    });

    // -- ext.flutterpilot.setLocale -------------------------------------------
    // Overrides the app locale at runtime. Pass `locale` as a language code
    // (e.g., `'fr'`, `'pt_BR'`). Use `'default'` to reset.
    registerExtension('ext.flutterpilot.setLocale', (method, parameters) async {
      final code = parameters['locale'];
      if (code == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 
          'Missing locale'
        );
      }
      try {
        if (code == 'default') {
          localeNotifier.value = null;
        } else {
          final parts = code.split('_');
          localeNotifier.value = parts.length > 1 
              ? ui.Locale(parts[0], parts[1]) 
              : ui.Locale(parts[0]);
        }
        return ServiceExtensionResponse.result(json.encode({'status': 'success'}));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, 
          'Error: $e'
        );
      }
    });

    // -- ext.flutterpilot.getPerfMetrics --------------------------------------
    // Returns the current FPS estimate and a timestamp.
    registerExtension('ext.flutterpilot.getPerfMetrics', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({
        'fps': _lastFps.toStringAsFixed(1),
        'timestamp': DateTime.now().toIso8601String(),
      }));
    });

    // -- ext.flutterpilot.navigateTo ------------------------------------------
    // Pushes a named route via `Navigator.of(context).pushNamed(route)`.
    // Requires `route` parameter.
    registerExtension('ext.flutterpilot.navigateTo', (method, parameters) async {
      final route = parameters['route'];
      final context = WidgetsBinding.instance.rootElement;
      if (route != null && context != null) {
        try {
          if (_isRecording) _recordAction('navigate', {'route': route});
          Navigator.of(context).pushNamed(route);
          return ServiceExtensionResponse.result(json.encode({'status': 'success'}));
        } catch (e) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError, 
            'Failed: $e'
          );
        }
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.invalidParams, 
        'Missing params'
      );
    });

    // -- ext.flutterpilot.startRecording --------------------------------------
    // Begins recording user interactions, navigations, and errors.
    // Clears any previously recorded actions.
    registerExtension('ext.flutterpilot.startRecording', (method, parameters) async {
      _isRecording = true;
      _recordedActions.clear();
      return ServiceExtensionResponse.result(json.encode({'status': 'started'}));
    });

    // -- ext.flutterpilot.stopRecording ---------------------------------------
    // Stops recording and returns all captured actions as a JSON array.
    registerExtension('ext.flutterpilot.stopRecording', (method, parameters) async {
      _isRecording = false;
      return ServiceExtensionResponse.result(json.encode({'actions': _recordedActions}));
    });

    // -- ext.flutterpilot.tapAt -----------------------------------------------
    // Simulates a tap at absolute screen coordinates (`x`, `y`).
    registerExtension('ext.flutterpilot.tapAt', (method, parameters) async {
      final x = double.tryParse(parameters['x'] ?? '');
      final y = double.tryParse(parameters['y'] ?? '');
      if (x == null || y == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 
          'Invalid coords'
        );
      }
      if (_isRecording) _recordAction('tapAt', {'x': x, 'y': y});
      await InteractionManager.tapAt(Offset(x, y));
      return ServiceExtensionResponse.result(json.encode({'status': 'success'}));
    });

    // -- ext.flutterpilot.tapWidget -------------------------------------------
    // Taps the center of a widget identified by its `key` string.
    // Looks up the element via [PilotWidgetInspector.findElementByKey].
    registerExtension('ext.flutterpilot.tapWidget', (method, parameters) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 
          'Missing key'
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, 
          'Widget not found'
        );
      }
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final pos = ro.localToGlobal(ro.size.center(Offset.zero));
        if (_isRecording) _recordAction('tapWidget', {'key': key});
        await InteractionManager.tapAt(pos);
        return ServiceExtensionResponse.result(json.encode({'status': 'success'}));
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError, 
        'No layout'
      );
    });

    // -- ext.flutterpilot.enterText -------------------------------------------
    // Sets the text content of a text field identified by `key`.
    // Walks descendants of the matched element to find an
    // [EditableTextState] and writes `text` to its controller.
    registerExtension('ext.flutterpilot.enterText', (method, parameters) async {
      final key = parameters['key'];
      final text = parameters['text'];
      if (key == null || text == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 
          'Missing params'
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, 
          'Widget not found'
        );
      }
      bool found = false;
      void findText(Element e) {
        if (found) return;
        if (e is StatefulElement && e.state is EditableTextState) {
          try {
            (e.state as dynamic).controller.text = text;
            found = true;
            if (_isRecording) _recordAction('enterText', {'key': key, 'text': text});
          } on NoSuchMethodError catch (_) {
            // Controller not accessible on this EditableTextState variant.
          }
          return;
        }
        e.visitChildren(findText);
      }
      findText(element);
      return found 
          ? ServiceExtensionResponse.result(json.encode({'status': 'success'})) 
          : ServiceExtensionResponse.error(
              ServiceExtensionResponse.extensionError, 
              'Not text field'
            );
    });

    // -- ext.flutterpilot.scrollIntoView --------------------------------------
    // Scrolls the widget identified by `key` into the visible viewport
    // using [Scrollable.ensureVisible].
    registerExtension('ext.flutterpilot.scrollIntoView', (method, parameters) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 
          'Missing key'
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, 
          'Widget not found'
        );
      }
      Scrollable.ensureVisible(element);
      return ServiceExtensionResponse.result(json.encode({'status': 'success'}));
    });

    // -- ext.flutterpilot.setState --------------------------------------------
    // Injects a state value using a setter previously registered via
    // [registerStateSetter]. Requires `type`, `name`, and `value` (JSON
    // string) parameters.
    registerExtension('ext.flutterpilot.setState', (method, parameters) async {
      final type = parameters['type'];
      final name = parameters['name'];
      final valueJson = parameters['value'];
      
      if (type == null || name == null || valueJson == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams, 
          'Missing type, name, or value'
        );
      }

      if (!_stateSetters.containsKey(type)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, 
          'No setter registered for type: $type'
        );
      }

      try {
        final dynamic value = json.decode(valueJson);
        final result = await _stateSetters[type]!(name, value);
        return ServiceExtensionResponse.result(json.encode({
          'status': 'success', 
          'result': _safeJsonEncode(result)
        }));
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, 
          'State injection failed: $e'
        );
      }
    });
  }

  static dynamic _safeJsonEncode(dynamic object) {
    if (object == null || object is num || object is bool || object is String) return object;
    if (object is Map) return object.map((k, v) => MapEntry(k.toString(), _safeJsonEncode(v)));
    if (object is Iterable) return object.map(_safeJsonEncode).toList();
    try { return (object as dynamic).toJson(); } on NoSuchMethodError catch (_) { return object.toString(); }
  }

  static Future<Uint8List?> _captureScreenshot() async {
    try {
      final pixelRatio = WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ?? 1.0;
      RenderRepaintBoundary? boundary;
      void findBoundary(RenderObject object) {
        if (boundary != null) return;
        if (object is RenderRepaintBoundary) { boundary = object; return; }
        object.visitChildren(findBoundary);
      }
      for (final rv in WidgetsBinding.instance.renderViews) { findBoundary(rv); }
      if (boundary != null) {
        final image = await boundary!.toImage(pixelRatio: pixelRatio);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      }
    } catch (e) { debugPrint('Screenshot error: $e'); }
    return null;
  }
}
