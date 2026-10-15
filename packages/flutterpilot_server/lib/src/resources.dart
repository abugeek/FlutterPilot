part of '../flutterpilot_server.dart';

/// One standard MCP resource this server offers (task 16).
///
/// The list is fixed, so `resources/list` is cheap; the live state is read on
/// demand by `resources/read`. Resources add nothing to `tools/list`, so they
/// never grow the token budget an agent pays before it calls anything.
class _ResourceSpec {
  const _ResourceSpec({
    required this.uri,
    required this.name,
    required this.mimeType,
    required this.description,
  });

  final String uri;
  final String name;
  final String mimeType;
  final String description;
}

/// The five resources, in `resources/list` order.
const _resourceSpecs = <_ResourceSpec>[
  _ResourceSpec(
    uri: 'flutterpilot://app/summary',
    name: 'App Summary',
    mimeType: 'application/json',
    description:
        'Live app state: connection, active device, platform, build mode, '
        'current route and error count. Read it to check state without a tool '
        'call.',
  ),
  _ResourceSpec(
    uri: 'flutterpilot://app/errors',
    name: 'Active App Errors',
    mimeType: 'application/json',
    description:
        'Uncaught exceptions and layout overflows with file locations and a '
        'freshness marker; entries from before the last reload are split out.',
  ),
  _ResourceSpec(
    uri: 'flutterpilot://app/widget-tree',
    name: 'Widget Tree',
    mimeType: 'text/plain',
    description:
        'Compact widget hierarchy of the current screen (types, keys, text and '
        'source locations), pruned of framework wrappers.',
  ),
  _ResourceSpec(
    uri: 'flutterpilot://app/logs',
    name: 'Debug Logs',
    mimeType: 'text/plain',
    description:
        'Recent console output (print, debugPrint, developer log), merged with '
        'what the SDK buffered before FlutterPilot connected.',
  ),
  _ResourceSpec(
    uri: 'flutterpilot://devices',
    name: 'Device Fleet',
    mimeType: 'application/json',
    description:
        'Registered devices with their VM-service address and which one is '
        'active.',
  ),
];

/// What every app-scoped resource says when nothing is connected.
const _noAppMessage = 'No Flutter app currently connected';

/// Live app data one resource read formats (task 16).
///
/// The server fills it from the connected app; a test can pass one to
/// [FlutterPilotServer.readResourceForTest] to exercise the connected branch
/// without a running app.
class ResourceAppData {
  const ResourceAppData({
    this.snapshot,
    this.errors,
    this.widgetTree,
    this.sdkLogs = const [],
    this.serverLogs = const [],
  });

  /// `ext.flutterpilot.getAppSnapshot` data (route, lifecycle, recent logs).
  final Map<String, dynamic>? snapshot;

  /// `ext.flutterpilot.getErrors` data.
  final Map<String, dynamic>? errors;

  /// `ext.flutterpilot.getWidgetTree` data (`{'tree': ...}`).
  final Map<String, dynamic>? widgetTree;

  /// The SDK's buffered console lines from before the connection.
  final List<Map<String, dynamic>> sdkLogs;

  /// Console lines captured since FlutterPilot connected, oldest first.
  final List<Map<String, dynamic>> serverLogs;
}

/// The same data as [ResourceAppData], plus whether an app is connected.
class _ResourceData {
  const _ResourceData({
    this.connected = false,
    this.snapshot,
    this.errors,
    this.widgetTree,
    this.sdkLogs = const [],
    this.serverLogs = const [],
  });

  final bool connected;
  final Map<String, dynamic>? snapshot;
  final Map<String, dynamic>? errors;
  final Map<String, dynamic>? widgetTree;
  final List<Map<String, dynamic>> sdkLogs;
  final List<Map<String, dynamic>> serverLogs;
}

/// Standard MCP resources (task 16): `resources/list` and `resources/read`,
/// so an agent can attach live app context without invoking a tool.
mixin _ResourcesMixin on _FlutterPilotServerBase {
  /// Registers the five standard resources. Called once, at construction.
  ///
  /// [McpServer.registerResource] adds the resources capability and a
  /// `resources/list_changed` notification; the constructor already declares
  /// `listChanged: true`, so sending that notification later is allowed.
  void _registerResources() {
    for (final spec in _resourceSpecs) {
      server.registerResource(spec.name, spec.uri, (
        description: spec.description,
        mimeType: spec.mimeType,
      ), (uri, _) => _readResource(uri));
    }
  }

  /// The list `resources/list` returns, for tests.
  List<Map<String, dynamic>> resourceListJson() => [
    for (final spec in _resourceSpecs)
      {
        'uri': spec.uri,
        'name': spec.name,
        'description': spec.description,
        'mimeType': spec.mimeType,
      },
  ];

  /// Reads one resource the way `resources/read` does, for tests.
  ///
  /// Without [app] it asks the connected app; pass [app] to exercise the
  /// connected branch with no running app. An unknown [uri] fails the way the
  /// protocol does.
  Future<ReadResourceResult> readResourceForTest(
    String uri, {
    ResourceAppData? app,
  }) async {
    final spec = _resourceFor(uri);
    if (spec == null) throw _unknownResource(uri);
    final data = app == null
        ? await _liveResourceData()
        : _ResourceData(
            connected: true,
            snapshot: app.snapshot,
            errors: app.errors,
            widgetTree: app.widgetTree,
            sdkLogs: app.sdkLogs.isEmpty
                ? _sdkLogsFrom(app.snapshot)
                : app.sdkLogs,
            serverLogs: app.serverLogs,
          );
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri,
          mimeType: spec.mimeType,
          text: _renderResource(spec, data),
        ),
      ],
    );
  }

  _ResourceSpec? _resourceFor(String uri) {
    for (final spec in _resourceSpecs) {
      if (spec.uri == uri) return spec;
    }
    return null;
  }

  static McpError _unknownResource(String uri) => McpError(
    ErrorCode.resourceNotFound.value,
    'Resource not found',
    {'uri': uri},
  );

  Future<ReadResourceResult> _readResource(Uri uri) async {
    final spec = _resourceFor(uri.toString());
    if (spec == null) throw _unknownResource(uri.toString());
    final data = await _liveResourceData();
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: spec.mimeType,
          text: _renderResource(spec, data),
        ),
      ],
    );
  }

  /// Gathers the live app data a resource read needs. Without a connected app
  /// this makes no VM call: the resources return their fallback.
  Future<_ResourceData> _liveResourceData() async {
    if (_activeContext?.service == null) return const _ResourceData();
    final snapshot = await _extensionData('ext.flutterpilot.getAppSnapshot');
    final errors = await _extensionData('ext.flutterpilot.getErrors');
    final tree = await _extensionData('ext.flutterpilot.getWidgetTree', const {
      'maxDepth': '20',
      'compact': 'true',
    });
    return _ResourceData(
      connected: true,
      snapshot: snapshot,
      errors: errors,
      widgetTree: tree,
      sdkLogs: _sdkLogsFrom(snapshot),
      serverLogs: _activeServerLogs,
    );
  }

  /// The SDK's newest console lines, from the app snapshot's `recentLogs`.
  static List<Map<String, dynamic>> _sdkLogsFrom(
    Map<String, dynamic>? snapshot,
  ) => ((snapshot?['recentLogs'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();

  /// [extension]'s data, or null when the app has no such extension (e.g. no
  /// SDK in zero-code mode): a resource still answers with what it has.
  Future<Map<String, dynamic>?> _extensionData(
    String extension, [
    Map<String, dynamic> parameters = const {},
  ]) async {
    final res = await _callExtensionRaw(extension, parameters);
    return res.isError ? null : res.data;
  }

  List<Map<String, dynamic>> get _activeServerLogs {
    final id = _fleetManager.activeDeviceId ?? 'default';
    return _debugLogBuffer
        .where((entry) => (entry['deviceId'] ?? 'default') == id)
        .toList();
  }

  String _renderResource(_ResourceSpec spec, _ResourceData data) {
    switch (spec.uri) {
      case 'flutterpilot://devices':
        return jsonEncode(_devicesResource(data));
      case 'flutterpilot://app/summary':
        if (!data.connected) return _noAppJson();
        return jsonEncode(_summaryResource(data));
      case 'flutterpilot://app/errors':
        if (!data.connected) return _noAppJson();
        return jsonEncode(_errorsResource(data));
      case 'flutterpilot://app/widget-tree':
        return data.connected ? _widgetTreeResource(data) : _noAppMessage;
      case 'flutterpilot://app/logs':
        return data.connected ? _logsResource(data) : _noAppMessage;
    }
    return _noAppJson();
  }

  static String _noAppJson() =>
      jsonEncode(const {'connected': false, 'message': _noAppMessage});

  Map<String, dynamic> _summaryResource(_ResourceData data) {
    final context = _activeContext;
    final snapshot = data.snapshot;
    return {
      'connected': true,
      'deviceId': _fleetManager.activeDeviceId ?? 'default',
      'platform': context?.operatingSystem,
      'buildMode': context?.buildMode?.name,
      'web': context?.isWeb ?? false,
      'sdkMode': _sdkMode(data),
      'sdkProtocol': context?.sdkProtocol,
      'lifecycle': snapshot?['lifecycle'] ?? context?.lifecycle,
      'route': snapshot?['route']?['current'],
      'routeDepth': snapshot?['route']?['stackDepth'],
      'errorCount': _freshErrorSplit(data).since.length,
      'reconnecting': _isReconnecting,
    };
  }

  Map<String, dynamic> _errorsResource(_ResourceData data) {
    final split = _freshErrorSplit(data);
    return {
      'connected': true,
      'sdkMode': _sdkMode(data),
      'count': split.since.length,
      'beforeReloadCount': split.before.length,
      'errors': [
        for (final error in split.since)
          _errorEntry(error, freshness: 'since-last-reload'),
      ],
      if (split.before.isNotEmpty)
        'beforeReload': [
          for (final error in split.before)
            _errorEntry(error, freshness: 'before-last-reload'),
        ],
    };
  }

  /// Splits the app's errors by the last reload, so a resource reports the
  /// same "is it healthy now?" as `get_errors` (error_freshness.dart).
  ({List<Map<String, dynamic>> since, List<Map<String, dynamic>> before})
  _freshErrorSplit(_ResourceData data) {
    final context = _activeContext;
    final List<Map<String, dynamic>> raw;
    if (data.errors != null) {
      raw = ((data.errors!['errors'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } else {
      raw = [...?context?.zeroCodeErrors];
    }
    return errorsByReload(raw, context?.lastReload);
  }

  String _sdkMode(_ResourceData data) {
    final reported = data.errors?['sdkMode']?.toString();
    if (reported != null) return reported;
    return switch (_activeContext?.hasSdk) {
      true => 'sdk',
      false => 'zero-code',
      _ => 'unknown',
    };
  }

  Map<String, dynamic> _errorEntry(
    Map<String, dynamic> error, {
    required String freshness,
  }) {
    final location = firstStackLocation(error['stackTrace']?.toString());
    return {
      'exception': error['exception']?.toString() ?? 'Unknown error',
      if (error['widget'] != null) 'widget': error['widget'],
      'location': ?location,
      if (error['timestamp'] != null) 'timestamp': error['timestamp'],
      'freshness': freshness,
    };
  }

  Map<String, dynamic> _devicesResource(_ResourceData data) => {
    ..._fleetManager.listDevices(),
    'connected': data.connected,
    'platform': _activeContext?.operatingSystem,
  };

  String _widgetTreeResource(_ResourceData data) {
    final tree = data.widgetTree?['tree'];
    if (tree is! Map) {
      return 'No widget tree available'
          '${_activeContext?.hasSdk == false ? ' (zero-code mode)' : ''}.';
    }
    final text = _widgetTreeText(Map<String, dynamic>.from(tree)).trimRight();
    return 'Widget tree (compact):\n$text';
  }

  static String _widgetTreeText(Map<String, dynamic> node, [int depth = 0]) {
    final buffer = StringBuffer('${'  ' * depth}${node['type'] ?? '?'}');
    final key = node['key']?.toString();
    if (key != null && key.isNotEmpty) buffer.write(' $key');
    final text = node['text']?.toString();
    if (text != null && text.isNotEmpty) buffer.write(' "$text"');
    final location = node['loc']?.toString();
    if (location != null && location.isNotEmpty) buffer.write(' ($location)');
    if (node['truncated'] == true) buffer.write(' …');
    buffer.writeln();
    for (final child in (node['children'] as List? ?? const [])) {
      if (child is Map) {
        buffer.write(
          _widgetTreeText(Map<String, dynamic>.from(child), depth + 1),
        );
      }
    }
    return buffer.toString();
  }

  /// Pre-connection (SDK-buffered) lines merged with the server's own capture,
  /// oldest first, repeats compacted — the same view `get_debug_logs` gives.
  String _logsResource(_ResourceData data) {
    final pre = preConnectionLogs(
      sdkLogs: data.sdkLogs,
      serverLogs: data.serverLogs,
    );
    final entries = [...pre, ...data.serverLogs];
    if (entries.isEmpty) return 'No console logs since FlutterPilot connected.';
    final lines = <String>[];
    String? prevMessage, prevLevel, prevLogger, prevTime;
    var repeat = 0;
    void flush() {
      if (prevMessage == null) return;
      final logger = (prevLogger?.isNotEmpty ?? false) ? '($prevLogger) ' : '';
      final suffix = repeat > 1 ? ' [x$repeat]' : '';
      lines.add('[$prevTime] [$prevLevel] $logger$prevMessage$suffix');
    }

    for (final entry in entries) {
      final message = entry['message']?.toString() ?? '';
      final level = entry['level']?.toString() ?? '';
      final logger = entry['logger']?.toString() ?? '';
      if (message == prevMessage &&
          level == prevLevel &&
          logger == prevLogger) {
        repeat++;
        continue;
      }
      flush();
      prevMessage = message;
      prevLevel = level;
      prevLogger = logger;
      prevTime = entry['timestamp']?.toString() ?? '';
      repeat = 1;
    }
    flush();
    final source = pre.isEmpty
        ? ''
        : ', ${pre.length} from before FlutterPilot connected';
    return '${entries.length} console entries$source:\n${lines.join('\n')}';
  }
}
