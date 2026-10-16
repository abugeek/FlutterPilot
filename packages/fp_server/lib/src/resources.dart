part of '../fp_server.dart';

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

/// What a resource says when the app/device changed mid-read (task 06 §7).
///
/// A read pins the connection it started against and re-checks it after every
/// await: rather than blend two apps into one response, it says the context
/// moved and asks to be read again.
const _contextChangedMessage =
    'The connected app or active device changed while this resource was being '
    'read; read it again for a coherent view.';

/// The app extensions the resources read (task 06).
const _extAppSnapshot = 'ext.flutterpilot.getAppSnapshot';
const _extErrors = 'ext.flutterpilot.getErrors';
const _extWidgetTree = 'ext.flutterpilot.getWidgetTree';
const _extWidgetProperties = 'ext.flutterpilot.getWidgetProperties';
const _extNavigationStack = 'ext.flutterpilot.getNavigationStack';
const _extGoRouterState = 'ext.flutterpilot.getGoRouterState';

/// Which app extensions each fixed resource reads, in order (task 06).
///
/// A read names exactly what it needs, so it never inherits another resource's
/// work. `flutterpilot://devices` asks the app for nothing — the fleet is the
/// server's own state — so a fleet read makes **zero** app VM calls. The
/// summary reads the snapshot and the error list but never builds a widget
/// tree. The errors, tree and logs each read one thing independently: a slow or
/// failing tree call cannot delay, fail or grow the others' responses.
const _resourceExtensions = <String, List<String>>{
  'flutterpilot://app/summary': [_extAppSnapshot, _extErrors],
  'flutterpilot://app/errors': [_extErrors],
  'flutterpilot://app/widget-tree': [_extWidgetTree],
  'flutterpilot://app/logs': [_extAppSnapshot],
  'flutterpilot://devices': <String>[],
};

/// The arguments one resource passes to [extension].
Map<String, dynamic> _resourceParameters(String extension) =>
    extension == _extWidgetTree
    ? const {'maxDepth': '20', 'compact': 'true'}
    : const {};

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

/// Live app data a templated resource read formats (task 26).
///
/// The server fills it from the connected app; a test can pass one to
/// [FlutterPilotServer.readWidgetResourceForTest] or
/// [FlutterPilotServer.readRouteResourceForTest] to exercise the connected
/// branch without a running app.
class ResourceTemplateData {
  const ResourceTemplateData({
    this.widgetProperties,
    this.widgetTree,
    this.navigationStack,
    this.routerState,
  });

  /// `ext.flutterpilot.getWidgetProperties` data for the requested key.
  final Map<String, dynamic>? widgetProperties;

  /// `ext.flutterpilot.getWidgetTree` data (`{'tree': ...}`) scoped to the key.
  final Map<String, dynamic>? widgetTree;

  /// `ext.flutterpilot.getNavigationStack` data (`{'stack': [...]}`).
  final Map<String, dynamic>? navigationStack;

  /// `ext.flutterpilot.getGoRouterState` data (go_router apps only).
  final Map<String, dynamic>? routerState;
}

/// The same data as [ResourceAppData], plus whether an app is connected.
class _ResourceData {
  const _ResourceData({
    this.connected = false,
    this.snapshot,
    this.errors,
    this.errorsUnavailable = false,
    this.widgetTree,
    this.sdkLogs = const [],
    this.serverLogs = const [],
  }) : contextChanged = false;

  /// A read whose app/device changed after it started: render the change, not
  /// a mixture of the two connections.
  const _ResourceData.changed()
    : connected = false,
      contextChanged = true,
      snapshot = null,
      errors = null,
      errorsUnavailable = false,
      widgetTree = null,
      sdkLogs = const [],
      serverLogs = const [];

  final bool connected;

  /// Whether the connection changed between this read's first and last await.
  final bool contextChanged;

  final Map<String, dynamic>? snapshot;
  final Map<String, dynamic>? errors;

  /// True when the error list was asked for but did not come back (missing
  /// extension, a failure or a lost connection), as opposed to a healthy empty
  /// list — so the resource never shows "could not ask" as "no errors".
  final bool errorsUnavailable;

  final Map<String, dynamic>? widgetTree;
  final List<Map<String, dynamic>> sdkLogs;
  final List<Map<String, dynamic>> serverLogs;
}

/// One app-extension read a resource performed (task 06).
///
/// [available] is false when the app has no such extension or the call failed,
/// which a resource reports distinctly from a healthy empty result.
class ResourceExtensionRead {
  const ResourceExtensionRead.available(this.data) : available = true;
  const ResourceExtensionRead.unavailable() : data = null, available = false;

  final Map<String, dynamic>? data;
  final bool available;
}

/// The app connection a live resource read talks to (task 06).
///
/// [generation] changes whenever the app reconnects or another device becomes
/// active; a read pins it at its start and re-checks after every await, so a
/// response never belongs to two connections at once.
abstract class ResourceAppConnection {
  const ResourceAppConnection();

  /// Whether an app is connected right now.
  bool get connected;

  /// The active device id.
  String get deviceId;

  /// The connection generation of the active device.
  int get generation;

  /// Reads one extension from the app.
  Future<ResourceExtensionRead> read(
    String extension,
    Map<String, dynamic> parameters,
  );
}

/// The server's real app connection, as a resource read sees it (task 06).
class _LiveResourceConnection implements ResourceAppConnection {
  const _LiveResourceConnection(this._server);

  final _FlutterPilotServerBase _server;

  @override
  bool get connected => _server._activeContext?.service != null;

  @override
  String get deviceId => _server._fleetManager.activeDeviceId ?? 'default';

  @override
  int get generation => _server._activeContext?.connectionGeneration ?? 0;

  @override
  Future<ResourceExtensionRead> read(
    String extension,
    Map<String, dynamic> parameters,
  ) async {
    final res = await _server._callExtensionRaw(extension, parameters);
    return res.isError
        ? const ResourceExtensionRead.unavailable()
        : ResourceExtensionRead.available(res.data);
  }
}

/// The app/device a resource read started against (task 06 §7).
class _ResourcePin {
  _ResourcePin(this._connection)
    : _connected = _connection.connected,
      _deviceId = _connection.deviceId,
      _generation = _connection.generation;

  final ResourceAppConnection _connection;
  final bool _connected;
  final String _deviceId;
  final int _generation;

  /// Whether the app is still the one this read began against.
  bool get isCurrent =>
      _connection.connected == _connected &&
      _connection.deviceId == _deviceId &&
      _connection.generation == _generation;
}

/// Standard MCP resources (task 16): `resources/list` and `resources/read`,
/// so an agent can attach live app context without invoking a tool.
mixin _ResourcesMixin on _FlutterPilotServerBase {
  /// Test seam (task 06): the app a live resource read talks to.
  ///
  /// **Null in production**, where the server's own connection is used. A test
  /// installs a fake to count the extensions each URI reads and to inject a
  /// missing extension, a failure, a device switch or a reconnect without a
  /// running app.
  ResourceAppConnection? resourceAppConnectionForTest;

  /// The app connection a live read talks to: the test fake, or the real one.
  ResourceAppConnection get _resourceConnection =>
      resourceAppConnectionForTest ?? _LiveResourceConnection(this);

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
    _registerResourceTemplates();
    _registerSubscriptionHandlers();
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
        ? await _liveResourceData(uri)
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
    final data = await _liveResourceData(uri.toString());
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

  /// Runs the read plan for [uri] against the live (or injected) app.
  ///
  /// Only the extensions that resource needs are read, and the connection is
  /// pinned so a device switch or a reconnect mid-read is reported rather than
  /// blended. Without a connected app this makes no app call: the resources
  /// return their fallback. `flutterpilot://devices` needs nothing, so a fleet
  /// read makes **zero** app VM calls even while connected.
  Future<_ResourceData> _liveResourceData(String uri) async {
    final connection = _resourceConnection;
    final pin = _ResourcePin(connection);
    if (!pin.isCurrent || !connection.connected) return const _ResourceData();
    Map<String, dynamic>? snapshot;
    Map<String, dynamic>? errors;
    var errorsUnavailable = false;
    Map<String, dynamic>? tree;
    for (final extension in _resourceExtensions[uri] ?? const <String>[]) {
      final read = await connection.read(
        extension,
        _resourceParameters(extension),
      );
      if (!pin.isCurrent) return const _ResourceData.changed();
      switch (extension) {
        case _extAppSnapshot:
          snapshot = read.data;
        case _extErrors:
          errors = read.data;
          errorsUnavailable = !read.available;
        case _extWidgetTree:
          tree = read.data;
      }
    }
    return _ResourceData(
      connected: true,
      snapshot: snapshot,
      errors: errors,
      errorsUnavailable: errorsUnavailable,
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

  /// [value] with every string run through [Redaction.text], structurally, so
  /// an encoded resource stays valid JSON (task 06 §10): a credential inside an
  /// exception message, a route's query string or a widget's text is masked
  /// without the quotes a naive text pass would strip.
  static Object? _redactStrings(Object? value) => switch (value) {
    final String text => Redaction.text(text),
    final Map map => {
      for (final MapEntry(:key, :value) in map.entries)
        '$key': _redactStrings(value),
    },
    final List list => [for (final item in list) _redactStrings(item)],
    _ => value,
  };

  List<Map<String, dynamic>> get _activeServerLogs {
    final id = _fleetManager.activeDeviceId ?? 'default';
    return _debugLogBuffer
        .where((entry) => (entry['deviceId'] ?? 'default') == id)
        .toList();
  }

  String _renderResource(_ResourceSpec spec, _ResourceData data) {
    if (data.contextChanged) {
      return spec.mimeType == 'text/plain'
          ? _contextChangedMessage
          : _contextChangedJson();
    }
    switch (spec.uri) {
      case 'flutterpilot://devices':
        return jsonEncode(_redactStrings(_devicesResource(data)));
      case 'flutterpilot://app/summary':
        if (!data.connected) return _noAppJson();
        return jsonEncode(_redactStrings(_summaryResource(data)));
      case 'flutterpilot://app/errors':
        if (!data.connected) return _noAppJson();
        return jsonEncode(_redactStrings(_errorsResource(data)));
      case 'flutterpilot://app/widget-tree':
        return data.connected ? _widgetTreeResource(data) : _noAppMessage;
      case 'flutterpilot://app/logs':
        return data.connected ? _logsResource(data) : _noAppMessage;
    }
    return _noAppJson();
  }

  static String _noAppJson() =>
      jsonEncode(const {'connected': false, 'message': _noAppMessage});

  static String _contextChangedJson() => jsonEncode(const {
    'connected': true,
    'contextChanged': true,
    'message': _contextChangedMessage,
  });

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
      // The error list was asked for but did not come back: never read
      // errorCount 0 as "clean" (task 06 §8).
      if (data.errorsUnavailable) 'errorsUnavailable': true,
      'reconnecting': _isReconnecting,
    };
  }

  Map<String, dynamic> _errorsResource(_ResourceData data) {
    final split = _freshErrorSplit(data);
    final since = split.since;
    final before = split.before;
    final shownSince = since.take(_Constants.maxResourceErrorItems).toList();
    final shownBefore = before.take(_Constants.maxResourceErrorItems).toList();
    final sinceNote = truncationNote(
      shown: shownSince.length,
      total: since.length,
      what: 'errors (newest kept)',
      how: 'the app buffer is the source; fix and reload to clear it',
    );
    final beforeNote = truncationNote(
      shown: shownBefore.length,
      total: before.length,
      what: 'errors from before the last reload',
      how: 'the app buffer is the source; a reload splits it',
    );
    return {
      'connected': true,
      'sdkMode': _sdkMode(data),
      'count': since.length,
      'beforeReloadCount': before.length,
      // Asked for and not delivered is not "no errors" (task 06 §8).
      if (data.errorsUnavailable) 'errorsUnavailable': true,
      'errors': [
        for (final error in shownSince)
          _errorEntry(error, freshness: 'since-last-reload'),
      ],
      if (shownBefore.isNotEmpty)
        'beforeReload': [
          for (final error in shownBefore)
            _errorEntry(error, freshness: 'before-last-reload'),
        ],
      if (sinceNote != null) 'truncated': true,
      'note': ?sinceNote,
      'beforeReloadNote': ?beforeNote,
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
      'exception': _clipResourceField(
        error['exception']?.toString() ?? 'Unknown error',
      ),
      if (error['widget'] != null)
        'widget': _clipResourceField(error['widget'].toString()),
      'location': ?_clipResourceField(location),
      if (error['timestamp'] != null) 'timestamp': error['timestamp'],
      'freshness': freshness,
    };
  }

  /// [text] cut to [_Constants.maxResourceErrorFieldChars], so a few huge
  /// entries keep the JSON bounded without cutting the serialized payload.
  static String? _clipResourceField(String? text) {
    if (text == null || text.length <= _Constants.maxResourceErrorFieldChars) {
      return text;
    }
    return '${text.substring(0, _Constants.maxResourceErrorFieldChars)}…';
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
    // App text can carry a credential; the compact tree is bounded to a byte
    // budget so one deep tree cannot blow the response up (task 06 §10).
    final text = FlutterPilotServer._boundToolText(
      Redaction.text(_widgetTreeText(Map<String, dynamic>.from(tree))),
    ).trimRight();
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
  ///
  /// Read on its own: a slow or failing widget-tree call never delays, fails or
  /// grows this response (task 06 §6). SDK-buffered lines are redacted here (the
  /// server's own capture is redacted when appended) and only the newest
  /// [_Constants.maxResourceLogEntries] are rendered.
  String _logsResource(_ResourceData data) {
    final pre = preConnectionLogs(
      sdkLogs: data.sdkLogs,
      serverLogs: data.serverLogs,
    );
    final all = [...pre, ...data.serverLogs];
    if (all.isEmpty) return 'No console logs since FlutterPilot connected.';
    final entries = all.length <= _Constants.maxResourceLogEntries
        ? all
        : all.sublist(all.length - _Constants.maxResourceLogEntries);
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
      final message = Redaction.text(entry['message']?.toString() ?? '');
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
    final note = truncationNote(
      shown: entries.length,
      total: all.length,
      what: 'console entries (newest kept)',
      how: 'Call get_debug_logs to narrow by level, query or logger.',
    );
    final lead = '${all.length} console entries$source:';
    return note == null
        ? '$lead\n${lines.join('\n')}'
        : '$lead\n$note\n${lines.join('\n')}';
  }

  /// Registers the dynamic (RFC 6570) resource templates (task 26).
  ///
  /// A template with a null `listCallback` contributes nothing to
  /// `resources/list`, so the five standard resources stay the only listed
  /// ones and `tools/list` does not grow a byte. A client discovers the
  /// templates through `resources/templates/list` and reads them by expanding
  /// the URI.
  void _registerResourceTemplates() {
    server.registerResourceTemplate(
      'widget_by_key',
      ResourceTemplateRegistration(
        'flutterpilot://app/widgets/{key}',
        listCallback: null,
      ),
      (
        description:
            'Compact widget hierarchy and properties for a specific widget '
            'Key.',
        mimeType: 'application/json',
      ),
      (uri, variables, _) =>
          _readWidgetResource(uri, variables['key']?.toString() ?? ''),
      title: 'Widget Subtree by Key',
    );
    server.registerResourceTemplate(
      'route_by_path',
      ResourceTemplateRegistration(
        'flutterpilot://app/routes/{path}',
        listCallback: null,
      ),
      (
        description:
            'Navigation state, matched route, and parameters for a specific '
            'route path or "current".',
        mimeType: 'application/json',
      ),
      (uri, variables, _) =>
          _readRouteResource(uri, variables['path']?.toString() ?? 'current'),
      title: 'Route Inspection',
    );
  }

  /// A templated resource URI built from [segments], so a key or route with a
  /// space, slash, quote or non-ASCII character is percent-encoded the way an
  /// RFC 6570 client would send it — the raw value is still what the app is
  /// asked for (task 06 §9).
  static Uri _templateUri(List<String> segments) =>
      Uri(scheme: 'flutterpilot', host: 'app', pathSegments: segments);

  /// Reads `flutterpilot://app/widgets/{key}`, for tests too.
  Future<ReadResourceResult> readWidgetResourceForTest(
    String key, {
    ResourceTemplateData? app,
  }) => _readWidgetResource(_templateUri(['widgets', key]), key, app: app);

  /// Reads `flutterpilot://app/routes/{path}`, for tests too.
  Future<ReadResourceResult> readRouteResourceForTest(
    String path, {
    ResourceTemplateData? app,
  }) => _readRouteResource(_templateUri(['routes', path]), path, app: app);

  Future<ReadResourceResult> _readWidgetResource(
    Uri uri,
    String key, {
    ResourceTemplateData? app,
  }) async => _jsonResource(uri, await _widgetResourceText(key, app));

  Future<ReadResourceResult> _readRouteResource(
    Uri uri,
    String path, {
    ResourceTemplateData? app,
  }) async => _jsonResource(uri, await _routeResourceText(path, app));

  static ReadResourceResult _jsonResource(Uri uri, String text) =>
      ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            mimeType: 'application/json',
            text: text,
          ),
        ],
      );

  /// The widget named by [key]: its own properties plus the keys of every
  /// descendant, so an agent can walk one subtree without pulling the whole
  /// tree.
  Future<String> _widgetResourceText(
    String key,
    ResourceTemplateData? app,
  ) async {
    final connection = app == null ? _resourceConnection : null;
    if (connection != null && !connection.connected) return _noAppJson();
    final pin = connection == null ? null : _ResourcePin(connection);

    final Map<String, dynamic>? properties;
    if (app != null) {
      properties = app.widgetProperties;
    } else {
      final read = await connection!.read(_extWidgetProperties, {'key': key});
      if (!pin!.isCurrent) return _contextChangedJson();
      properties = read.data;
    }
    if (properties == null) {
      return jsonEncode(
        _redactStrings({'connected': true, 'found': false, 'key': key}),
      );
    }
    final Map<String, dynamic>? tree;
    if (app != null) {
      tree = app.widgetTree;
    } else {
      final read = await connection!.read(_extWidgetTree, {
        'rootKey': key,
        'maxDepth': '12',
        'compact': 'true',
      });
      if (!pin!.isCurrent) return _contextChangedJson();
      tree = read.data;
    }
    final node = tree?['tree'];
    final childKeys = <String>[];
    // The outermost node is the widget itself; its key is already `key`.
    _collectChildKeys(node, childKeys);
    final total = childKeys.length;
    final listed = total <= _Constants.maxResourceChildKeys
        ? childKeys
        : childKeys.sublist(0, _Constants.maxResourceChildKeys);
    return jsonEncode(
      _redactStrings({
        'connected': true,
        'found': true,
        'key': key,
        'widget': properties,
        if (node is Map) 'tree': node,
        'childKeys': listed,
        if (total > listed.length) 'childKeysTotal': total,
        if (total > listed.length) 'childKeysTruncated': true,
      }),
    );
  }

  /// Every key written under [node], depth-first.
  static void _collectChildKeys(Object? node, List<String> keys) {
    if (node is! Map) return;
    for (final child in (node['children'] as List?) ?? const []) {
      if (child is! Map) continue;
      final key = child['key']?.toString();
      if (key != null && key.isNotEmpty) keys.add(key);
      _collectChildKeys(child, keys);
    }
  }

  /// The navigation state for [path]: the route stack, and, when go_router is
  /// present, the matched route, path/query parameters and `canPop`.
  /// `current` (the default) reports the route on screen.
  Future<String> _routeResourceText(
    String path,
    ResourceTemplateData? app,
  ) async {
    final connection = app == null ? _resourceConnection : null;
    if (connection != null && !connection.connected) return _noAppJson();
    final pin = connection == null ? null : _ResourcePin(connection);

    final Map<String, dynamic>? stackData;
    if (app != null) {
      stackData = app.navigationStack;
    } else {
      final read = await connection!.read(_extNavigationStack, const {});
      if (!pin!.isCurrent) return _contextChangedJson();
      stackData = read.data;
    }
    final Map<String, dynamic>? router;
    if (app != null) {
      router = app.routerState;
    } else {
      final read = await connection!.read(_extGoRouterState, const {});
      if (!pin!.isCurrent) return _contextChangedJson();
      router = read.data;
    }
    final fullStack = ((stackData?['stack'] as List?) ?? const [])
        .map((entry) => entry.toString())
        .toList();
    final stack = fullStack.length <= _Constants.maxResourceRouteItems
        ? fullStack
        : fullStack.sublist(
            fullStack.length - _Constants.maxResourceRouteItems,
          );
    final currentRoute =
        router?['currentLocation']?.toString() ??
        (stack.isEmpty ? null : stack.last);
    final matchedRoutes = ((router?['matchedRoutes'] as List?) ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
    final requested = path.trim().isEmpty ? 'current' : path.trim();
    final isCurrent = requested == 'current';
    final found =
        isCurrent ||
        requested == currentRoute ||
        fullStack.contains(requested) ||
        matchedRoutes.any(
          (route) => route['matchedLocation']?.toString() == requested,
        );
    final target = isCurrent ? currentRoute : (found ? requested : null);
    var matched = _matchedRoute(matchedRoutes, target);
    if (matched == null && isCurrent && matchedRoutes.isNotEmpty) {
      // No exact match for the location: the last entry is the deepest.
      matched = matchedRoutes.last;
    }
    final routerMap = router ?? const <String, dynamic>{};
    final hasRouter = router != null;
    final allMatched = (routerMap['matchedRoutes'] as List?) ?? const [];
    final matchedListed = allMatched.length <= _Constants.maxResourceRouteItems
        ? allMatched
        : allMatched.sublist(0, _Constants.maxResourceRouteItems);
    return jsonEncode(
      _redactStrings({
        'connected': true,
        'requested': requested,
        'found': found,
        'currentRoute': currentRoute,
        'stack': stack,
        'stackDepth': fullStack.length,
        if (fullStack.length > stack.length) 'stackTruncated': true,
        'goRouter': hasRouter,
        if (hasRouter) 'canPop': routerMap['canPop'],
        'route': ?matched,
        'pathParameters':
            routerMap['pathParameters'] ?? const <String, dynamic>{},
        'queryParameters':
            routerMap['queryParameters'] ?? const <String, dynamic>{},
        if (hasRouter && routerMap['matchedRoutes'] != null)
          'matchedRoutes': matchedListed,
        if (hasRouter && allMatched.length > matchedListed.length)
          'matchedRoutesTotal': allMatched.length,
      }),
    );
  }

  static Map<String, dynamic>? _matchedRoute(
    List<Map<String, dynamic>> routes,
    String? location,
  ) {
    if (location == null) return null;
    for (final route in routes) {
      if (route['matchedLocation']?.toString() == location) return route;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Live subscriptions (task 27): `resources/subscribe` / `resources/unsubscribe`
  // and `notifications/resources/updated`, so a client that attaches a resource
  // is pushed a fresh read on a hot reload, navigation, a crash or a device
  // change instead of polling.
  // ---------------------------------------------------------------------------

  /// The URIs the connected client subscribed to.
  ///
  /// A stdio server has one client, so a plain set is enough; a subscription
  /// lasts until the client unsubscribes (or the process ends).
  final Set<String> _subscribedResourceUris = {};

  /// Registers `resources/subscribe` / `resources/unsubscribe`.
  ///
  /// The constructor declares `resources: (subscribe: true)`, so mcp_dart
  /// accepts handlers for these methods; without one a client would get
  /// `-32601 Method not found`.
  void _registerSubscriptionHandlers() {
    server.server.setRequestHandler<JsonRpcSubscribeRequest>(
      Method.resourcesSubscribe,
      (request, extra) async {
        _subscribedResourceUris.add(request.subParams.uri);
        return const EmptyResult();
      },
      (id, params, meta) => JsonRpcSubscribeRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.resourcesSubscribe,
        'params': params,
        '_meta': ?meta,
      }),
    );

    server.server.setRequestHandler<JsonRpcUnsubscribeRequest>(
      Method.resourcesUnsubscribe,
      (request, extra) async {
        _subscribedResourceUris.remove(request.unsubParams.uri);
        return const EmptyResult();
      },
      (id, params, meta) => JsonRpcUnsubscribeRequest.fromJson({
        'jsonrpc': jsonRpcVersion,
        'id': id,
        'method': Method.resourcesUnsubscribe,
        'params': params,
        '_meta': ?meta,
      }),
    );

    _registerSubscriptionTestTrigger();
  }

  /// Emits `notifications/resources/updated` for [uri] when a client has
  /// subscribed to it, and does nothing otherwise.
  ///
  /// Called on the app events that change what a resource would read. Reading
  /// is the client's job: the notification only says "read me again".
  @override
  Future<void> notifyResourceUpdated(String uri) async {
    if (!_subscribedResourceUris.contains(uri)) return;
    await server.server.sendResourceUpdated(
      ResourceUpdatedNotification(uri: uri),
    );
  }

  /// [notifyResourceUpdated], for tests: raises the same push an app event
  /// would, so a protocol test can drive the cycle deterministically. The
  /// `FLUTTERPILOT_TEST_RESOURCES` trigger below calls it, so Matrix 5 in
  /// mcp_protocol_compliance_test.dart exercises this seam over real stdio.
  Future<void> notifyResourceUpdatedForTest(String uri) =>
      notifyResourceUpdated(uri);

  /// The RPC method the headless compliance suite drives to raise a resource
  /// update on demand.
  ///
  /// With no Flutter app attached a real event (a reload, a navigation, a
  /// crash) cannot happen, and the suite must still prove the push path end to
  /// end. Only registered when the harness sets `FLUTTERPILOT_TEST_RESOURCES`,
  /// so it is absent from a normal server.
  static const _testTriggerMethod = 'flutterpilot/_test/notifyResourceUpdated';

  void _registerSubscriptionTestTrigger() {
    if (Platform.environment['FLUTTERPILOT_TEST_RESOURCES'] != '1') return;
    server.server.setRequestHandler<JsonRpcRequest>(
      _testTriggerMethod,
      (request, extra) async {
        await notifyResourceUpdatedForTest(
          request.params?['uri']?.toString() ?? '',
        );
        return const EmptyResult();
      },
      (id, params, meta) => JsonRpcRequest(
        id: id,
        method: _testTriggerMethod,
        params: params,
        meta: meta,
      ),
    );
  }
}
