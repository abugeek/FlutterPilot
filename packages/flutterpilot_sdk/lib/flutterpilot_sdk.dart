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

/// The core class for FlutterPilot SDK.
class FlutterPilot {
  FlutterPilot._();

  static bool _initialized = false;
  static final Map<String, Function> _customTools = {};
  static final Map<String, Future<dynamic> Function(String name, dynamic value)> _stateSetters = {};
  static bool _isRecording = false;
  static final List<Map<String, dynamic>> _recordedActions = [];
  
  /// Global notifier for locale overrides.
  static final ValueNotifier<ui.Locale?> localeNotifier = ValueNotifier(null);

  static double _lastFps = 0;
  static int _frameCount = 0;
  static DateTime _lastFpsUpdate = DateTime.now();

  /// Initializes the FlutterPilot SDK and registers service extensions.
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

  /// Registers a custom tool that can be called by the AI.
  static void registerCustomTool(String name, Function callback) {
    _customTools[name] = callback;
  }

  /// Registers a state setter for a specific type (e.g., 'riverpod').
  static void registerStateSetter(String type, Future<dynamic> Function(String name, dynamic value) setter) {
    _stateSetters[type] = setter;
  }

  /// Logs a state change if recording is active.
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

  static void _registerServiceExtensions() {
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

    registerExtension('ext.flutterpilot.ping', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({
        'status': 'ok', 
        'version': '0.0.1'
      }));
    });

    registerExtension('ext.flutterpilot.getErrors', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({
        'errors': ErrorInspector.errors
      }));
    });

    registerExtension('ext.flutterpilot.listCustomTools', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({
        'tools': _customTools.keys.toList()
      }));
    });

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

    registerExtension('ext.flutterpilot.getNavigationStack', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({
        'stack': NavigationTracker.stack
      }));
    });

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

    registerExtension('ext.flutterpilot.getPerfMetrics', (method, parameters) async {
      return ServiceExtensionResponse.result(json.encode({
        'fps': _lastFps.toStringAsFixed(1),
        'timestamp': DateTime.now().toIso8601String(),
      }));
    });

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

    registerExtension('ext.flutterpilot.startRecording', (method, parameters) async {
      _isRecording = true;
      _recordedActions.clear();
      return ServiceExtensionResponse.result(json.encode({'status': 'started'}));
    });

    registerExtension('ext.flutterpilot.stopRecording', (method, parameters) async {
      _isRecording = false;
      return ServiceExtensionResponse.result(json.encode({'actions': _recordedActions}));
    });

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
