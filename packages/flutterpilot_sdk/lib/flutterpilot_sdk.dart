import 'dart:convert';
import 'dart:developer';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
  static final Map<String, String? Function(String name)> _stateReaders = {};
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
        'exception': details.exceptionAsString(),
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
    // -- ext.flutterpilot.getSummary ------------------------------------------
    // Returns a high-level snapshot: current route, error count, recording
    // state, and total widget count.
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
          'isRecording': _isRecording,
          'widgetCount': root != null
              ? PilotWidgetInspector.countElements(root)
              : 0,
        }),
      );
    });

    // -- ext.flutterpilot.ping ------------------------------------------------
    // Health-check endpoint. Returns SDK version.
    registerExtension('ext.flutterpilot.ping', (method, parameters) async {
      return ServiceExtensionResponse.result(
        json.encode({'status': 'ok', 'version': '0.0.1'}),
      );
    });

    // -- ext.flutterpilot.getErrors -------------------------------------------
    // Returns the buffered error list from [ErrorInspector].
    registerExtension('ext.flutterpilot.getErrors', (method, parameters) async {
      return ServiceExtensionResponse.result(
        json.encode({'errors': ErrorInspector.errors}),
      );
    });

    // -- ext.flutterpilot.listCustomTools -------------------------------------
    // Lists names of all tools registered via [registerCustomTool].
    registerExtension('ext.flutterpilot.listCustomTools', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({'tools': _customTools.keys.toList()}),
      );
    });

    // -- ext.flutterpilot.callCustomTool --------------------------------------
    // Invokes a custom tool by `name`. Extra params are forwarded to the
    // callback. Returns `invalidParams` if the tool name is missing or unknown.
    registerExtension('ext.flutterpilot.callCustomTool', (
      method,
      parameters,
    ) async {
      final name = parameters['name'];
      if (name == null || !_customTools.containsKey(name)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Tool not found',
        );
      }
      try {
        final result = await _customTools[name]!(parameters);
        return ServiceExtensionResponse.result(
          json.encode({'result': _safeJsonEncode(result)}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Error: $e',
        );
      }
    });

    // -- ext.flutterpilot.getWidgetTree ---------------------------------------
    // Captures the full widget tree as a nested JSON structure via
    // [PilotWidgetInspector.captureWidgetTree].
    registerExtension('ext.flutterpilot.getWidgetTree', (
      method,
      parameters,
    ) async {
      try {
        return ServiceExtensionResponse.result(
          json.encode({'tree': PilotWidgetInspector.captureWidgetTree()}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Error: $e',
        );
      }
    });

    // -- ext.flutterpilot.captureScreenshot -----------------------------------
    // Returns a base64-encoded PNG screenshot of the current render tree.
    registerExtension('ext.flutterpilot.captureScreenshot', (
      method,
      parameters,
    ) async {
      try {
        final bytes = await _captureScreenshot();
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

    // -- ext.flutterpilot.getNavigationStack ----------------------------------
    // Returns the ordered navigation route stack from [NavigationTracker].
    registerExtension('ext.flutterpilot.getNavigationStack', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({'stack': NavigationTracker.stack}),
      );
    });

    // -- ext.flutterpilot.setLocale -------------------------------------------
    // Overrides the app locale at runtime. Pass `locale` as a language code
    // (e.g., `'fr'`, `'pt_BR'`). Use `'default'` to reset.
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
          localeNotifier.value = null;
        } else {
          final parts = code.split('_');
          localeNotifier.value = parts.length > 1
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

    // -- ext.flutterpilot.getPerfMetrics --------------------------------------
    // Returns the current FPS estimate and a timestamp.
    registerExtension('ext.flutterpilot.getPerfMetrics', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({
          'fps': _lastFps.toStringAsFixed(1),
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    });

    // -- ext.flutterpilot.navigateTo ------------------------------------------
    // Pushes a named route. Uses [NavigationTracker.navigatorState] first
    // (direct reference via NavigatorObserver), then falls back to the root
    // element context if no tracker is registered.
    // Requires `route` parameter.
    registerExtension('ext.flutterpilot.navigateTo', (
      method,
      parameters,
    ) async {
      final route = parameters['route'];
      if (route == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: route',
        );
      }
      try {
        // Prefer navigator obtained directly from NavigationTracker observer
        // (bypasses the need for a BuildContext inside the navigator scope).
        final nav = NavigationTracker.navigatorState;
        if (nav != null && nav.mounted) {
          if (_isRecording) _recordAction('navigate', {'route': route});
          nav.pushNamed(route);
          return ServiceExtensionResponse.result(
            json.encode({'status': 'success', 'route': route}),
          );
        }
        // Fallback: try rootElement (works when app is simple / no overlay)
        final context = WidgetsBinding.instance.rootElement;
        if (context != null) {
          if (_isRecording) _recordAction('navigate', {'route': route});
          Navigator.of(context, rootNavigator: true).pushNamed(route);
          return ServiceExtensionResponse.result(
            json.encode({'status': 'success', 'route': route}),
          );
        }
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No Navigator available. Ensure NavigationTracker() is added to '
          'navigatorObservers in your MaterialApp.',
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Navigation failed: $e',
        );
      }
    });

    // -- ext.flutterpilot.startRecording --------------------------------------
    // Begins recording user interactions, navigations, and errors.
    // Clears any previously recorded actions.
    registerExtension('ext.flutterpilot.startRecording', (
      method,
      parameters,
    ) async {
      _isRecording = true;
      _recordedActions.clear();
      return ServiceExtensionResponse.result(
        json.encode({'status': 'started'}),
      );
    });

    // -- ext.flutterpilot.stopRecording ---------------------------------------
    // Stops recording and returns all captured actions as a JSON array.
    registerExtension('ext.flutterpilot.stopRecording', (
      method,
      parameters,
    ) async {
      _isRecording = false;
      return ServiceExtensionResponse.result(
        json.encode({'actions': _recordedActions}),
      );
    });

    // -- ext.flutterpilot.tapAt -----------------------------------------------
    // Simulates a tap at absolute screen coordinates (`x`, `y`).
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

    // -- ext.flutterpilot.tapWidget -------------------------------------------
    // Taps the center of a widget identified by its `key` string.
    // Looks up the element via [PilotWidgetInspector.findElementByKey].
    registerExtension('ext.flutterpilot.tapWidget', (method, parameters) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found',
        );
      }
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final pos = ro.localToGlobal(ro.size.center(Offset.zero));
        if (_isRecording) _recordAction('tapWidget', {'key': key});
        await InteractionManager.tapAt(pos);
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success'}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'No layout',
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
          'Missing params',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found',
        );
      }
      bool found = false;
      void findText(Element e) {
        if (found) return;
        if (e is StatefulElement && e.state is EditableTextState) {
          try {
            (e.state as dynamic).controller.text = text;
            found = true;
            if (_isRecording) {
              _recordAction('enterText', {'key': key, 'text': text});
            }
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
              'Not text field',
            );
    });

    // -- ext.flutterpilot.scrollIntoView --------------------------------------
    // Scrolls the widget identified by `key` into the visible viewport
    // using [Scrollable.ensureVisible].
    registerExtension('ext.flutterpilot.scrollIntoView', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found',
        );
      }
      Scrollable.ensureVisible(element);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
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
          'Missing type, name, or value',
        );
      }

      if (!_stateSetters.containsKey(type)) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No setter registered for type: $type',
        );
      }

      try {
        final dynamic value = json.decode(valueJson);
        final result = await _stateSetters[type]!(name, value);
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success', 'result': _safeJsonEncode(result)}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'State injection failed: $e',
        );
      }
    });

    // -- ext.flutterpilot.doubleTapWidget -------------------------------------
    registerExtension('ext.flutterpilot.doubleTapWidget', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final pos = ro.localToGlobal(ro.size.center(Offset.zero));
        if (_isRecording) _recordAction('doubleTapWidget', {'key': key});
        await InteractionManager.doubleTapAt(pos);
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success'}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'No layout for widget: $key',
      );
    });

    // -- ext.flutterpilot.longPressWidget -------------------------------------
    registerExtension('ext.flutterpilot.longPressWidget', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      final ms = int.tryParse(parameters['durationMs'] ?? '600') ?? 600;
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final pos = ro.localToGlobal(ro.size.center(Offset.zero));
        if (_isRecording) {
          _recordAction('longPressWidget', {'key': key, 'durationMs': ms});
        }
        await InteractionManager.longPressAt(
          pos,
          duration: Duration(milliseconds: ms),
        );
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success'}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'No layout for widget: $key',
      );
    });

    // -- ext.flutterpilot.swipeWidget -----------------------------------------
    // Swipes from the center of a widget in a given direction.
    // direction: up | down | left | right
    // distance: pixels to travel (default 200)
    registerExtension('ext.flutterpilot.swipeWidget', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      final direction = parameters['direction'] ?? 'up';
      final distance =
          double.tryParse(parameters['distance'] ?? '200') ?? 200.0;
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $key',
        );
      }
      final ro = element.renderObject;
      if (ro is! RenderBox || !ro.hasSize) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No layout for widget: $key',
        );
      }
      final start = ro.localToGlobal(ro.size.center(Offset.zero));
      final Offset end;
      switch (direction) {
        case 'up':
          end = start.translate(0, -distance);
        case 'down':
          end = start.translate(0, distance);
        case 'left':
          end = start.translate(-distance, 0);
        case 'right':
          end = start.translate(distance, 0);
        default:
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'direction must be up|down|left|right',
          );
      }
      if (_isRecording) {
        _recordAction('swipeWidget', {
          'key': key,
          'direction': direction,
          'distance': distance,
        });
      }
      await InteractionManager.swipeFromTo(start, end);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.dragWidget ------------------------------------------
    // Drags from one widget (by key) to another (by key).
    registerExtension('ext.flutterpilot.dragWidget', (
      method,
      parameters,
    ) async {
      final fromKey = parameters['fromKey'];
      final toKey = parameters['toKey'];
      if (fromKey == null || toKey == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing fromKey or toKey',
        );
      }
      final fromEl = PilotWidgetInspector.findElementByKey(fromKey);
      final toEl = PilotWidgetInspector.findElementByKey(toKey);
      if (fromEl == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $fromKey',
        );
      }
      if (toEl == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $toKey',
        );
      }
      final fromRo = fromEl.renderObject;
      final toRo = toEl.renderObject;
      if (fromRo is! RenderBox ||
          !fromRo.hasSize ||
          toRo is! RenderBox ||
          !toRo.hasSize) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No layout for one or both widgets',
        );
      }
      final from = fromRo.localToGlobal(fromRo.size.center(Offset.zero));
      final to = toRo.localToGlobal(toRo.size.center(Offset.zero));
      if (_isRecording) {
        _recordAction('dragWidget', {'fromKey': fromKey, 'toKey': toKey});
      }
      await InteractionManager.dragFromTo(from, to);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.waitForWidget ---------------------------------------
    // Polls every 100ms until a widget with `key` is found or `timeoutMs` elapses.
    registerExtension('ext.flutterpilot.waitForWidget', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      final timeoutMs = int.tryParse(parameters['timeoutMs'] ?? '5000') ?? 5000;
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
      while (DateTime.now().isBefore(deadline)) {
        final element = PilotWidgetInspector.findElementByKey(key);
        if (element != null) {
          return ServiceExtensionResponse.result(
            json.encode({'status': 'found', 'key': key}),
          );
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'Timeout: widget "$key" not found within ${timeoutMs}ms',
      );
    });

    // -- ext.flutterpilot.waitForRoute ----------------------------------------
    // Polls until the current route matches `route` or timeout.
    registerExtension('ext.flutterpilot.waitForRoute', (
      method,
      parameters,
    ) async {
      final route = parameters['route'];
      final timeoutMs = int.tryParse(parameters['timeoutMs'] ?? '5000') ?? 5000;
      if (route == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing route',
        );
      }
      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
      while (DateTime.now().isBefore(deadline)) {
        final current = NavigationTracker.currentRoute;
        if (current == route) {
          return ServiceExtensionResponse.result(
            json.encode({'status': 'reached', 'route': route}),
          );
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      final current = NavigationTracker.currentRoute;
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'Timeout: route "$route" not reached within ${timeoutMs}ms (currently on "$current")',
      );
    });

    // -- ext.flutterpilot.waitForAnimation ------------------------------------
    // Waits until the scheduler has no pending frames (all animations settled).
    registerExtension('ext.flutterpilot.waitForAnimation', (
      method,
      parameters,
    ) async {
      final timeoutMs = int.tryParse(parameters['timeoutMs'] ?? '3000') ?? 3000;
      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
      while (DateTime.now().isBefore(deadline)) {
        if (!SchedulerBinding.instance.hasScheduledFrame) {
          // Wait one more frame to be sure the last frame has been painted.
          await Future.delayed(const Duration(milliseconds: 16));
          if (!SchedulerBinding.instance.hasScheduledFrame) {
            return ServiceExtensionResponse.result(
              json.encode({'status': 'settled'}),
            );
          }
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'timeout',
          'note': 'Animation may still be running',
        }),
      );
    });

    // -- ext.flutterpilot.assertWidgetVisible ---------------------------------
    // Returns success if a widget with `key` exists and has layout, error otherwise.
    registerExtension('ext.flutterpilot.assertWidgetVisible', (
      method,
      parameters,
    ) async {
      final key = parameters['key'];
      if (key == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key',
        );
      }
      final element = PilotWidgetInspector.findElementByKey(key);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'ASSERTION FAILED: widget "$key" not found in tree',
        );
      }
      final ro = element.renderObject;
      if (ro is! RenderBox || !ro.hasSize) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'ASSERTION FAILED: widget "$key" found but has no layout (off-screen?)',
        );
      }
      return ServiceExtensionResponse.result(
        json.encode({'status': 'passed', 'key': key}),
      );
    });

    // -- ext.flutterpilot.assertTextVisible -----------------------------------
    // Returns success if any Text/RichText widget in the tree contains `text`.
    registerExtension('ext.flutterpilot.assertTextVisible', (
      method,
      parameters,
    ) async {
      final text = parameters['text'];
      final exact = parameters['exact'] == 'true';
      if (text == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing text',
        );
      }
      bool found = false;
      void findText(Element e) {
        if (found) return;
        if (e.widget is Text) {
          final data = (e.widget as Text).data ?? '';
          found = exact ? data == text : data.contains(text);
        } else if (e.widget is RichText) {
          final plain = (e.widget as RichText).text.toPlainText();
          found = exact ? plain == text : plain.contains(text);
        }
        if (!found) e.visitChildren(findText);
      }

      final root = WidgetsBinding.instance.rootElement;
      if (root != null) findText(root);
      if (found) {
        return ServiceExtensionResponse.result(
          json.encode({'status': 'passed', 'text': text}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'ASSERTION FAILED: text "$text" not visible on screen',
      );
    });

    // -- ext.flutterpilot.assertWidgetCount -----------------------------------
    // Returns success if the count of widgets of `type` matches `count`.
    registerExtension('ext.flutterpilot.assertWidgetCount', (
      method,
      parameters,
    ) async {
      final type = parameters['type'];
      final expectedStr = parameters['count'];
      if (type == null || expectedStr == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing type or count',
        );
      }
      final expected = int.tryParse(expectedStr);
      if (expected == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'count must be an integer',
        );
      }
      int actual = 0;
      void countWidgets(Element e) {
        if (e.widget.runtimeType.toString() == type) actual++;
        e.visitChildren(countWidgets);
      }

      final root = WidgetsBinding.instance.rootElement;
      if (root != null) countWidgets(root);
      if (actual == expected) {
        return ServiceExtensionResponse.result(
          json.encode({'status': 'passed', 'type': type, 'count': actual}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'ASSERTION FAILED: expected $expected "$type" widgets but found $actual',
      );
    });

    // -- ext.flutterpilot.waitForState ----------------------------------------
    // Polls until the named provider/cubit's current value string contains
    // `expectedValue`, or until `timeoutMs` elapses.
    // type: riverpod | bloc
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
      final reader = _stateReaders[type];
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

    // -- ext.flutterpilot.setOrientation --------------------------------------
    // Switches device orientation. orientation: portrait | landscape
    registerExtension('ext.flutterpilot.setOrientation', (
      method,
      parameters,
    ) async {
      final orientation = parameters['orientation'];
      final List<DeviceOrientation> preferred;
      switch (orientation) {
        case 'portrait':
          preferred = [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ];
        case 'landscape':
          preferred = [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ];
        case 'all':
          preferred = DeviceOrientation.values;
        default:
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'orientation must be: portrait | landscape | all',
          );
      }
      await SystemChrome.setPreferredOrientations(preferred);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success', 'orientation': orientation}),
      );
    });
  }

  static dynamic _safeJsonEncode(dynamic object) {
    if (object == null || object is num || object is bool || object is String) {
      return object;
    }
    if (object is Map) {
      return object.map((k, v) => MapEntry(k.toString(), _safeJsonEncode(v)));
    }
    if (object is Iterable) {
      return object.map(_safeJsonEncode).toList();
    }
    try {
      return (object as dynamic).toJson();
    } on NoSuchMethodError catch (_) {
      return object.toString();
    }
  }

  static Future<Uint8List?> _captureScreenshot() async {
    try {
      final pixelRatio =
          WidgetsBinding
              .instance
              .platformDispatcher
              .implicitView
              ?.devicePixelRatio ??
          1.0;
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
        final image = await boundary!.toImage(pixelRatio: pixelRatio);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Screenshot error: $e');
    }
    return null;
  }
}
