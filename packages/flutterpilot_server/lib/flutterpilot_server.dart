import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:logging/logging.dart' as logging;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:vm_service/vm_service.dart';

import 'src/build_mode.dart';
import 'src/cpu_profile.dart';
import 'src/fleet_compare.dart';
import 'src/fleet_manager.dart';
import 'src/frame_timeline.dart';
import 'src/http_detail.dart';
import 'src/image_budget.dart';
import 'src/memory_leaks.dart';
import 'src/native_crash.dart';
import 'src/device_runtime_context.dart';
import 'src/param_aliases.dart';
import 'src/plugin_tools.dart';
import 'src/redaction.dart';
import 'src/reload_failure.dart';
import 'src/scenario.dart';
import 'src/self_heal_manager.dart';
import 'src/test_writer.dart';
import 'src/verification.dart';
import 'src/vm_discovery.dart';
import 'src/web_limits.dart';
import 'src/window_size.dart';
import 'src/zero_code.dart';

export 'src/cli.dart' show runFlutterPilotServer;

part 'src/constants.dart';
part 'src/tools/app_inspection_tools.dart';
part 'src/tools/devtools_tools.dart';
part 'src/tools/native_automation_tools.dart';
part 'src/tools/navigation_tools.dart';
part 'src/tools/screenshot_tools.dart';
part 'src/tools/self_heal_tools.dart';
part 'src/tools/state_management_tools.dart';
part 'src/tools/testing_tools.dart';
part 'src/tools/test_generation_tools.dart';
part 'src/tools/scenario_tools.dart';
part 'src/tools/verification_tools.dart';
part 'src/tools/plugin_integration_tools.dart';
part 'src/tools/ui_automation_tools.dart';

final _log = logging.Logger('FlutterPilotServer');

/// Zone key run_on_devices sets to send each call to one device.
const _pinnedDevice = #flutterpilotPinnedDevice;

/// Base class exposing the members that tool mixins need.
abstract class _FlutterPilotServerBase {
  bool get staticTools;

  /// Every registered tool by name, for showing only the usable ones.
  final Map<String, RegisteredTool> _allTools = {};

  /// Every tool's callback by name, for tools that run another tool
  /// (profile_action).
  final Map<String, ToolFunction> _toolCallbacks = {};

  /// Where the connected app runs, to find its crash report if it dies.
  CrashTarget? _crashTarget;

  /// Started when the connection drops; cleared when an app connects.
  NativeCrashWatch? _nativeCrash;

  /// Between verify_feature(criteria) and verify_feature(finish): every
  /// action and check is evidence for the current criterion.
  Verification? _verification;

  /// Between generate_test(start) and generate_test(name): mocks are
  /// recorded too.
  bool _recordingTest = false;

  /// Adds a step only the server sees (a mocked response) to the recording.
  Future<void> _noteTestStep(Map<String, dynamic> step) async {
    if (!_recordingTest) return;
    await _callExtensionRaw('ext.flutterpilot.testRecording', {
      'action': 'note',
      'step': jsonEncode(step),
    });
  }

  /// Registers a tool. An unexpected exception becomes an error that names
  /// the tool and the cause — mcp_dart would replace it with a bare
  /// "Tool execution failed." and log the reason where the agent can't see it.
  RegisteredTool _tool(
    String name, {
    String? description,
    ToolInputSchema? inputSchema,
    required ToolFunction callback,
  }) {
    // An argument the tool doesn't have was dropped without a word:
    // get_network_logs(clear: true) answered with the logs and cleared
    // nothing (field test #280). Checked here so the tools that run other
    // tools (profile_action, run_on_devices, a leak-check cycle) refuse too.
    final properties = inputSchema?.properties?.keys ?? const <String>[];
    Future<CallToolResult> checked(
      Map<String, dynamic> args,
      RequestHandlerExtra extra,
    ) async {
      final unknown = unknownToolArguments(args.keys, [
        ...properties,
        'deviceId', // refused with its own message in _registerTool
      ]);
      if (unknown.isEmpty) return callback(args, extra);
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text:
                '$name has no ${unknown.map((a) => '"$a"').join(', ')} '
                'parameter${unknown.length == 1 ? '' : 's'}; nothing was '
                'done. ${properties.isEmpty ? 'It takes no arguments.' : 'It takes: ${properties.join(', ')}.'}',
          ),
        ],
      );
    }

    _toolCallbacks[name] = checked;
    return _allTools[name] = _registerTool(
      name,
      description: description,
      inputSchema: inputSchema,
      callback: checked,
    );
  }

  /// A tool failing because the app is gone says why, when the OS
  /// recorded a native crash (ROADMAP §5.8).
  Future<CallToolResult> _withNativeCrash(CallToolResult result) async {
    final crash = await _nativeCrash?.current();
    if (crash == null) return result;
    return CallToolResult(
      isError: true,
      content: [
        ...result.content,
        TextContent(
          text:
              '${crash.describe()}\nFix the cause, then start the app again '
              '(flutter run); FlutterPilot reconnects by itself.',
        ),
      ],
    );
  }

  RegisteredTool _registerTool(
    String name, {
    String? description,
    ToolInputSchema? inputSchema,
    required ToolFunction callback,
  }) => server.registerTool(
    name,
    description: description,
    inputSchema: inputSchema,
    callback: (args, extra) async {
      // Only some tools used to take a per-call device, and most ignored it:
      // answering from another device than the one asked for is worse than
      // refusing.
      if (args.containsKey('deviceId')) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text:
                  'Tools have no deviceId parameter: call '
                  'switch_device(id: "${args['deviceId']}") first; every tool '
                  'then targets that device.',
            ),
          ],
        );
      }
      try {
        var result = await callback(args, extra);
        if (result.isError) result = await _withNativeCrash(result);
        _verification?.record(
          name,
          args,
          result.content.whereType<TextContent>().map((c) => c.text).join('\n'),
          isError: result.isError == true,
        );
        final images = result.content.whereType<ImageContent>();
        if (!images.any((i) => i.data.length > maxImageBase64Chars)) {
          return result;
        }
        return CallToolResult(
          isError: result.isError,
          content: [
            for (final c in result.content)
              c is ImageContent
                  ? ImageContent(
                      data: fitBase64Png(c.data),
                      mimeType: c.mimeType,
                    )
                  : c,
            TextContent(text: '(Image scaled down to fit the size limit.)'),
          ],
        );
      } catch (e) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text:
                  '$name failed: $e. If the app was busy or reloading, retry; '
                  'call get_app_summary to check its state.',
            ),
          ],
        );
      }
    },
  );

  McpServer get server;
  String get vmServiceUri;
  bool get allowDestructive;
  bool get allowRemoteConnections;
  String? get remoteAccessToken;
  VmService? get _vmService;
  bool get _isReconnecting;
  Queue<Map<String, dynamic>> get _eventBuffer;
  Queue<Map<String, dynamic>> get _debugLogBuffer;
  void _clearDebugLogBuffer();
  Map<String, Uint8List> get _screenshotBaselines;
  int get _screenshotBaselineBytes;
  set _screenshotBaselineBytes(int value);
  SelfHealManager get _selfHealManager;
  FleetManager get _fleetManager;

  Future<bool> _connectWithUri([String? targetUri]);

  /// The VM service URI of the current connection (unredacted).
  String? get _connectedUri;

  /// Runtime state of the active device, once connected.
  DeviceRuntimeContext? get _activeContext;

  /// Recomputes which tools are listed (after the fleet changes).
  Future<void> _refreshToolVisibility();

  bool _isAllowedConnectionUri(String rawUri);

  /// A device was registered under a new name: its runtime state follows.
  Future<void> _renameDeviceContext(String from, String to);

  Future<VmService?> _vmServiceForParameters(Map<String, dynamic> parameters);

  Future<DeviceRuntimeContext?> _deviceContextForParameters(
    Map<String, dynamic> parameters,
  );

  Future<_ExtensionResult> _callExtensionRaw(
    String extension,
    Map<String, dynamic> parameters,
  );

  void _registerAppTool({
    required String name,
    required String description,
    required String extension,
    Map<String, JsonSchema>? properties,
    String Function(Map<String, dynamic> json)? formatResult,
  });

  /// Whether [name] is a Riverpod provider or a Bloc/Cubit ("riverpod" or
  /// "bloc"): the one whose plugin lists it, else the plugin the app has.
  Future<String> _stateTypeOf(String name) async {
    String? available;
    for (final (type, ext) in [
      ('riverpod', 'ext.flutterpilot.getRiverpodStates'),
      ('bloc', 'ext.flutterpilot.getBlocStates'),
    ]) {
      final res = await _callExtensionRaw(ext, {});
      if (res.isError) continue;
      available ??= type;
      final states = res.data?['states'];
      if (states is Map && states.containsKey(name)) return type;
    }
    return available ?? 'riverpod';
  }

  /// Returns an MCP error for an operation that mutates app data when the
  /// server was not explicitly started with --allow-destructive.
  CallToolResult _destructiveOperationDenied();
}

/// FlutterPilot MCP Server — bridges AI agents to a running Flutter app.
class FlutterPilotServer extends _FlutterPilotServerBase
    with
        _AppInspectionToolsMixin,
        _UiAutomationToolsMixin,
        _NativeAutomationToolsMixin,
        _NavigationToolsMixin,
        _ScreenshotToolsMixin,
        _SelfHealToolsMixin,
        _StateManagementToolsMixin,
        _TestingToolsMixin,
        _DevtoolsToolsMixin,
        _TestGenerationToolsMixin,
        _ScenarioToolsMixin,
        _VerificationToolsMixin,
        _PluginIntegrationToolsMixin {
  @override
  final McpServer server;
  String? _vmServiceUri;
  @override
  String get vmServiceUri => _redactVmServiceUri(_vmServiceUri ?? '');
  @override
  @override
  final bool allowDestructive;
  @override
  final bool allowRemoteConnections;
  @override
  final String? remoteAccessToken;

  /// `-p`: the only place to look for the app when given.
  final Directory? _explicitProjectRoot;

  /// The MCP client's workspace folders (`roots/list`), searched with the
  /// working directory when no `-p` was given.
  List<Directory> _clientRoots = const [];

  Directory get _projectRoot => _explicitProjectRoot ?? Directory.current;

  List<Directory> get _discoveryRoots => _explicitProjectRoot != null
      ? [_explicitProjectRoot]
      : [Directory.current, ..._clientRoots];
  @override
  VmService? _vmService;
  @override
  final Queue<Map<String, dynamic>> _eventBuffer = Queue();
  int _eventBufferBytes = 0;
  @override
  final Queue<Map<String, dynamic>> _debugLogBuffer = Queue();
  int _debugLogBufferBytes = 0;
  @override
  late final SelfHealManager _selfHealManager;
  @override
  late final FleetManager _fleetManager = FleetManager();
  @override
  final Map<String, Uint8List> _screenshotBaselines = {};
  @override
  int _screenshotBaselineBytes = 0;

  // Reconnection state
  @override
  bool _isReconnecting = false;
  bool _disposed = false;
  String? _cachedMainIsolateId;
  Timer? _reconnectTimer;
  Duration _currentBackoff = const Duration(seconds: 1);
  static const Duration _minBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 30);
  static final Random _random = Random();
  int _connectionGeneration = 0;
  int _nextOperationId = 0;
  final Map<String, DeviceRuntimeContext> _deviceContexts = {};

  /// Lists every tool from the start and never changes the list
  /// (`--static-tools`): for MCP clients that don't fetch it again after
  /// `tools/list_changed` and would keep a stale one. A tool that can't
  /// work on the connected app says why when called. The docs generator
  /// sets FLUTTERPILOT_LIST_ALL_TOOLS for the same list.
  @override
  final bool staticTools;

  FlutterPilotServer({
    String? vmServiceUri,
    this.allowDestructive = false,
    this.allowRemoteConnections = false,
    this.remoteAccessToken,
    Directory? projectRoot,
    bool staticTools = false,
  }) : staticTools =
           staticTools ||
           Platform.environment['FLUTTERPILOT_LIST_ALL_TOOLS'] != null,
       _vmServiceUri = vmServiceUri,
       _explicitProjectRoot = projectRoot,
       server = McpServer(
         Implementation(name: 'FlutterPilot', version: '0.1.0'),
         options: McpServerOptions(
           capabilities: ServerCapabilities(
             tools: ServerCapabilitiesTools(listChanged: true),
           ),
         ),
       ) {
    _selfHealManager = SelfHealManager(server: server);
    _registerTools();
    _registerPrompts();
    server.server.oninitialized = () => unawaited(_refreshClientRoots());
    server.server.setNotificationHandler<JsonRpcRootsListChangedNotification>(
      Method.notificationsRootsListChanged,
      (_) => _refreshClientRoots(),
      (params, meta) => JsonRpcRootsListChangedNotification.fromJson({
        'jsonrpc': jsonRpcVersion,
        'method': Method.notificationsRootsListChanged,
        'params': ?params,
      }),
    );
  }

  /// Reads the client's workspace folders and, if no app is connected yet,
  /// looks for one there — so the server finds the app without `-p` even
  /// when the client starts it outside the project.
  Future<void> _refreshClientRoots() async {
    if (_explicitProjectRoot != null ||
        server.server.getClientCapabilities()?.roots == null) {
      return;
    }
    try {
      final result = await server.server.listRoots();
      _clientRoots = [
        for (final root in result.roots)
          if (Uri.tryParse(root.uri) case final uri? when uri.scheme == 'file')
            Directory.fromUri(uri),
      ];
      _log.info(
        'Workspace roots: ${_clientRoots.map((d) => d.path).join(', ')}',
      );
    } catch (e) {
      _log.fine('roots/list failed: $e');
      return;
    }
    if (_vmService == null && (_vmServiceUri?.isEmpty ?? true)) {
      try {
        await _connectToVmService();
      } catch (e) {
        _log.fine('Connect after roots/list failed: $e');
      }
    }
  }

  Future<void> start() async {
    try {
      await _connectToVmService();
    } catch (e) {
      _log.warning('Initial VM Service connection skipped: $e');
    }

    // Start MCP server over stdio
    final stdioTransport = StdioServerTransport();
    await server.connect(stdioTransport);
    _log.info('FlutterPilot MCP Server started 🚀');
  }

  // ---------------------------------------------------------------------------
  // VM Service connection & reconnection
  // ---------------------------------------------------------------------------

  @override
  String? get _connectedUri => _vmService == null ? null : _vmServiceUri;

  @override
  DeviceRuntimeContext? get _activeContext =>
      _deviceContexts[_fleetManager.activeDeviceId ?? 'default'];

  @override
  Future<void> _renameDeviceContext(String from, String to) async {
    final context = _deviceContexts.remove(from);
    if (context == null) return;
    await _deviceContexts.remove(to)?.dispose();
    _deviceContexts[to] = context..deviceId = to;
  }

  @override
  Future<bool> _connectWithUri([String? targetUri]) async {
    if (targetUri != null && targetUri.isNotEmpty) {
      targetUri = normalizeVmServiceUri(targetUri) ?? targetUri;
      if (!_isAllowedConnectionUri(targetUri)) {
        _log.warning(
          'Blocked remote VM Service URI; enable allowRemoteConnections to connect.',
        );
        return false;
      }
      _vmServiceUri = targetUri;
    }
    if (_vmServiceUri == null || _vmServiceUri!.isEmpty) {
      _log.info('Auto-discovering running Flutter app...');
      final discovered = await VmDiscoveryService.discover(
        roots: _discoveryRoots,
      );
      if (discovered != null) {
        _vmServiceUri = discovered;
        _log.info('Discovered VM Service: $_vmServiceUri');
      } else {
        return false;
      }
    }
    try {
      await _connectToVmService();
      return _vmService != null;
    } catch (e) {
      _log.warning('Failed to connect to VM Service: $e');
      return false;
    }
  }

  Future<void>? _connecting;

  Future<void>? _sdkExtensionsReady;

  /// Right after launch (notably on web, via DWDS) the app may not have
  /// registered FlutterPilot's extensions yet. Wait for them once per
  /// connection, at most 5 s, instead of misreporting "Zero-Code mode" or
  /// "not registered" for the first calls. Only apps without the SDK that
  /// just started pay the wait: an isolate running for over 10 s has
  /// registered everything it will.
  /// Returns whether the SDK is installed, or null when the check failed.
  static Future<bool?> _waitForSdkExtensions(VmService vm) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final isolates = (await vm.getVM()).isolates ?? const <IsolateRef>[];
        var settled = isolates.isNotEmpty;
        for (final ref in isolates) {
          final isolate = await vm.getIsolate(ref.id!);
          if (isolate.extensionRPCs?.any(
                (e) => e.startsWith('ext.flutterpilot.'),
              ) ??
              false) {
            return true;
          }
          final started = isolate.startTime;
          settled &=
              started != null &&
              DateTime.now().millisecondsSinceEpoch - started > 10000;
        }
        if (settled) return false;
      } catch (_) {
        return null; // Connection trouble is reported by the call itself.
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  /// Tool calls and the reconnect timer can both trigger a connect; share one
  /// attempt so they never race into two live connections.
  Future<void> _connectToVmService() => _connecting ??= _doConnectToVmService()
      .whenComplete(() => _connecting = null);

  Future<void> _doConnectToVmService() async {
    if (_disposed) return;
    if (_vmServiceUri == null || _vmServiceUri!.isEmpty) {
      final discovered = await VmDiscoveryService.discover(
        roots: _discoveryRoots,
      );
      if (discovered != null) {
        _vmServiceUri = discovered;
      } else {
        _log.info(
          'No running Flutter app found yet. ${VmDiscoveryService.howToStart}',
        );
        return;
      }
    }
    // Discovery and CLI flags may yield the http:// form flutter run prints.
    _vmServiceUri = normalizeVmServiceUri(_vmServiceUri!) ?? _vmServiceUri;
    if (!_isAllowedConnectionUri(_vmServiceUri!)) {
      _log.warning(
        'Blocked remote VM Service URI; enable allowRemoteConnections to connect.',
      );
      return;
    }
    _log.info(
      'Connecting to VM Service: ${_redactVmServiceUri(_vmServiceUri!)}',
    );

    try {
      _vmService = await connectVmService(_vmServiceUri!);
    } catch (_) {
      // The app was most likely restarted on a new port: rediscover it
      // instead of retrying a dead URI forever.
      final found = await VmDiscoveryService.discover(roots: _discoveryRoots);
      final discovered = found == null ? null : normalizeVmServiceUri(found);
      final owner = discovered == null
          ? null
          : _fleetManager.idForUri(discovered);
      if (discovered == null ||
          discovered == _vmServiceUri ||
          !_isAllowedConnectionUri(discovered) ||
          // Another registered device's app, not this one restarted.
          (owner != null && owner != _fleetManager.activeDeviceId)) {
        rethrow;
      }
      _log.info('App restarted; rediscovered VM Service.');
      _vmServiceUri = discovered;
      _vmService = await connectVmService(discovered);
    }
    _log.info(
      'Connected to VM Service at ${_redactVmServiceUri(_vmServiceUri!)}',
    );
    _connectionGeneration++;
    // Also refreshes the entry after the app restarted on a new port, so
    // list_connected_devices / switch_device never hold a dead URI.
    _fleetManager.registerDevice(
      _fleetManager.activeDeviceId ?? 'default',
      _vmServiceUri!,
    );
    final activeDevice = _fleetManager.activeDeviceId ?? 'default';
    final activeContext =
        _deviceContexts[activeDevice] ??
        DeviceRuntimeContext(deviceId: activeDevice, uri: _vmServiceUri!);
    if (activeContext.service != null &&
        !identical(activeContext.service, _vmService)) {
      await activeContext.dispose();
    }
    activeContext.uri = _vmServiceUri!;
    _deviceContexts[activeDevice] = activeContext;
    activeContext.service = _vmService;
    activeContext.connectionGeneration = _connectionGeneration;
    activeContext.cachedMainIsolateId = null;
    activeContext.hasSdk = null;
    activeContext.lifecycle = null;
    activeContext.zeroCodeErrors.clear();
    final checkedService = _vmService!;
    _sdkExtensionsReady = _waitForSdkExtensions(checkedService).then((found) {
      if (!identical(activeContext.service, checkedService)) return;
      activeContext.hasSdk = found;
      if (found != null) _refreshToolVisibility();
    });
    try {
      _nativeCrash = null;
      final vm = await _vmService!.getVM();
      activeContext.operatingSystem = vm.operatingSystem;
      activeContext.targetCPU = vm.targetCPU;
      try {
        activeContext.buildMode = buildModeFromFlags(
          (await _vmService!.getFlagList()).flags ?? const [],
        );
        _scheduleToolVisibility();
      } catch (_) {}
      await _updateNativeToolVisibility(vm.operatingSystem, pid: vm.pid);
      _crashTarget = vm.pid == null || vm.operatingSystem == null
          ? null
          : CrashTarget(
              pid: vm.pid!,
              operatingSystem: vm.operatingSystem!,
              since: DateTime.now(),
              simulatorUdid: _simulatorApp?.udid,
            );
    } catch (_) {
      // Visibility is best-effort; the tools still explain themselves.
    }

    _currentBackoff = _minBackoff;
    _reconnectTimer?.cancel();
    _isReconnecting = false;

    // ignore: unawaited_futures
    final connectedService = _vmService!;
    connectedService.onDone
        .then((_) {
          // A replaced connection closing is expected; only react to the live one.
          if (_disposed || !identical(_vmService, connectedService)) return;
          _log.warning('VM Service connection lost');
          _scheduleReconnect();
        })
        .catchError((Object e) {
          if (_disposed || !identical(_vmService, connectedService)) return;
          _log.warning('Error in VM Service done handler: $e');
          _scheduleReconnect();
        });

    await _setupEventStreaming(activeContext);
  }

  @override
  bool _isAllowedConnectionUri(String rawUri) {
    final uri = Uri.tryParse(rawUri);
    final host = uri?.host.toLowerCase();
    final local =
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '[::1]';
    if (local) return true;
    if (!allowRemoteConnections || uri == null) return false;
    // Dart VM service authentication is carried in the URI path token.
    // Refuse remote endpoints without one, even when remote access is enabled.
    final hasVmToken = uri.pathSegments.any((segment) => segment.isNotEmpty);
    if (!hasVmToken) return false;
    if (remoteAccessToken == null || remoteAccessToken!.isEmpty) return true;
    return uri.pathSegments
        .map(Uri.decodeComponent)
        .contains(remoteAccessToken);
  }

  static String _redactVmServiceUri(String rawUri) {
    final uri = Uri.tryParse(rawUri);
    if (uri == null || uri.pathSegments.isEmpty) return rawUri;
    return uri.replace(path: '/<redacted>').toString();
  }

  void _scheduleReconnect() {
    // However the loss was noticed (the socket closing, or a call failing
    // first), find out whether the app crashed; once per connection.
    final target = _crashTarget;
    if (target != null && _nativeCrash == null && !_disposed) {
      _nativeCrash = NativeCrashWatch(target);
    }
    if (_isReconnecting || _disposed) return;
    _isReconnecting = true;
    _vmService = null;
    _cachedMainIsolateId = null;
    final activeContext =
        _deviceContexts[_fleetManager.activeDeviceId ?? 'default'];
    if (activeContext != null) {
      activeContext.cachedMainIsolateId = null;
      activeContext.service = null;
      activeContext.connectionGeneration++;
    }
    _attemptReconnect();
  }

  void _attemptReconnect() {
    if (_disposed) return;

    final jitter =
        (_currentBackoff.inMilliseconds * 0.25 * (2 * _random.nextDouble() - 1))
            .round();
    final delay = Duration(
      milliseconds: _currentBackoff.inMilliseconds + jitter,
    );

    _log.info(
      'Reconnecting to VM Service in ${delay.inMilliseconds}ms '
      '(backoff: ${_currentBackoff.inSeconds}s)',
    );

    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;
      try {
        await _connectToVmService();
        _isReconnecting = false;
        _log.info('VM Service reconnected successfully');
      } catch (e) {
        _log.warning('Reconnection attempt failed', e);
        _currentBackoff = Duration(
          milliseconds: (_currentBackoff.inMilliseconds * 2).clamp(
            _minBackoff.inMilliseconds,
            _maxBackoff.inMilliseconds,
          ),
        );
        _attemptReconnect();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Event streaming
  // ---------------------------------------------------------------------------

  Future<void> _setupEventStreaming(DeviceRuntimeContext context) async {
    final service = context.service;
    if (service == null) return;

    await context.extensionEvents?.cancel();
    context.extensionEvents = null;
    await context.loggingEvents?.cancel();
    context.loggingEvents = null;
    await context.stdoutEvents?.cancel();
    context.stdoutEvents = null;
    await context.serviceEvents?.cancel();
    context.serviceEvents = null;
    await context.isolateEvents?.cancel();
    context.isolateEvents = null;
    context.registeredServices.clear();

    // The VM service replays ServiceRegistered for already-registered services
    // (flutter_tools' reloadSources/hotRestart) right after subscribing, so
    // attach the listener before streamListen or those events are dropped.
    try {
      context.serviceEvents = service.onServiceEvent.listen((Event event) {
        final name = event.service;
        if (name == null) return;
        if (event.kind == EventKind.kServiceRegistered &&
            event.method != null) {
          context.registeredServices[name] = event.method!;
        } else if (event.kind == EventKind.kServiceUnregistered) {
          context.registeredServices.remove(name);
        }
      });
      await service.streamListen(EventStreams.kService);
    } catch (e) {
      _log.fine('Could not subscribe to Service stream: $e');
    }

    // The SDK's extensions can register after the connect-time check (slow
    // web startup, or a restart after "flutterpilot init"): list its tools then.
    try {
      context.isolateEvents = service.onIsolateEvent.listen((Event event) {
        // Hot restart starts a new isolate; the SDK's error buffer resets
        // with it, so the zero-code one does too.
        if (event.kind == EventKind.kIsolateStart) {
          context.zeroCodeErrors.clear();
        }
        // Plugins register when the app sets them up (after Firebase init,
        // a first Dio, ...): list their tools then.
        if (event.kind == EventKind.kServiceExtensionAdded &&
            (event.extensionRPC?.startsWith('ext.flutterpilot.') ?? false)) {
          context.hasSdk = true;
          if (identical(context, _activeContext)) _scheduleToolVisibility();
        }
      });
      await service.streamListen(EventStreams.kIsolate);
    } catch (e) {
      _log.fine('Could not subscribe to Isolate stream: $e');
    }

    try {
      await service.streamListen(EventStreams.kExtension);
      context.extensionEvents = service.onExtensionEvent.listen(
        (Event event) async {
          try {
            final timestamp = DateTime.now().toIso8601String();
            if (event.extensionKind == 'ext.flutterpilot.error') {
              final data = event.extensionData?.data;
              final exception =
                  data?['exception']?.toString() ?? 'Unknown Exception';
              final severity = data?['severity']?.toString() ?? 'error';
              _appendEvent({
                'type': 'error',
                'timestamp': timestamp,
                'data': data,
              }, deviceId: context.deviceId);

              await _selfHealManager.handleCrash(
                exception: exception,
                severity: severity,
                deviceId: context.deviceId,
              );
            } else if (event.extensionKind == 'Flutter.Error' &&
                context.hasSdk != true) {
              // Without the SDK, Flutter's structured errors are the only
              // error source (on by default in debug builds, except web).
              final data = event.extensionData?.data;
              if (data == null) return;
              final error = errorFromFlutterErrorEvent(data, DateTime.now());
              context.zeroCodeErrors.add(error);
              if (context.zeroCodeErrors.length > 50) {
                context.zeroCodeErrors.removeAt(0);
              }
              if (context.hasSdk == false) {
                _appendEvent({
                  'type': 'error',
                  'timestamp': timestamp,
                  'data': error,
                }, deviceId: context.deviceId);
              }
            } else if (event.extensionKind == 'ext.flutterpilot.lifecycle') {
              context.lifecycle = event.extensionData?.data['state']
                  ?.toString();
            }
          } catch (e) {
            _log.warning('Error processing extension event: $e');
          }
        },
        onError: (Object error) {
          _log.warning('Extension event stream error', error);
        },
        onDone: () {
          if (!identical(context.service, service)) return;
          _log.info('Extension event stream closed');
          context.service = null;
          context.connectionGeneration++;
          if (context.deviceId == _fleetManager.activeDeviceId) {
            _vmService = null;
          }
          if (!_disposed && context.deviceId == _fleetManager.activeDeviceId) {
            _scheduleReconnect();
          }
        },
      );
    } catch (e) {
      _log.warning('Could not subscribe to extension stream', e);
    }

    try {
      await service.streamListen(EventStreams.kLogging);
      context.loggingEvents = service.onLoggingEvent.listen(
        (Event event) {
          final record = event.logRecord;
          if (record == null) return;
          _appendDebugLog(
            message: record.message?.valueAsString ?? '',
            level: _levelToString(record.level ?? 0),
            logger: record.loggerName?.valueAsString ?? '',
            timestamp: DateTime.now().toIso8601String(),
            deviceId: context.deviceId,
          );
        },
        onError: (Object error) {
          _log.fine('Logging stream error: $error');
        },
      );
    } catch (e) {
      _log.fine(
        'Could not subscribe to Logging stream (may not be available): $e',
      );
    }

    try {
      await service.streamListen(EventStreams.kStdout);
      context.stdoutEvents = service.onStdoutEvent.listen(
        (Event event) {
          final bytes = event.bytes;
          if (bytes == null || bytes.isEmpty) return;
          final raw = utf8
              .decode(base64.decode(bytes), allowMalformed: true)
              .trim();
          if (raw.isEmpty) return;
          _appendDebugLog(
            message: raw,
            level: 'info',
            logger: 'stdout',
            timestamp: DateTime.now().toIso8601String(),
            deviceId: context.deviceId,
          );
        },
        onError: (Object error) {
          _log.fine('Stdout stream error: $error');
        },
      );
    } catch (e) {
      _log.fine(
        'Could not subscribe to Stdout stream (may not be available): $e',
      );
    }
  }

  void _appendDebugLog({
    required String message,
    required String level,
    required String logger,
    required String timestamp,
    String? deviceId,
  }) {
    final entry = <String, dynamic>{
      'deviceId': deviceId ?? _fleetManager.activeDeviceId ?? 'default',
      'timestamp': timestamp,
      'level': level,
      'logger': logger,
      // App output may print credentials (security review).
      'message': Redaction.text(message),
    };
    _debugLogBuffer.add(entry);
    _debugLogBufferBytes += _entryBytes(entry);
    _trimDebugLogBuffer();
  }

  void _appendEvent(Map<String, dynamic> entry, {String? deviceId}) {
    final deviceEntry = <String, dynamic>{
      'deviceId': deviceId ?? _fleetManager.activeDeviceId ?? 'default',
      ...entry,
    };
    _eventBuffer.add(deviceEntry);
    _eventBufferBytes += _entryBytes(deviceEntry);
    while (_eventBuffer.length > _Constants.eventBufferMax ||
        _eventBufferBytes > _Constants.eventBufferMaxBytes) {
      _eventBufferBytes -= _entryBytes(_eventBuffer.removeFirst());
    }
  }

  void _trimDebugLogBuffer() {
    while (_debugLogBuffer.length > _Constants.debugLogBufferMax ||
        _debugLogBufferBytes > _Constants.debugLogBufferMaxBytes) {
      _debugLogBufferBytes -= _entryBytes(_debugLogBuffer.removeFirst());
    }
  }

  static int _entryBytes(Map<String, dynamic> entry) =>
      utf8.encode(jsonEncode(entry)).length;

  @override
  void _clearDebugLogBuffer() {
    _debugLogBuffer.clear();
    _debugLogBufferBytes = 0;
  }

  static String _levelToString(int level) {
    if (level >= 1000) return 'error';
    if (level >= 900) return 'warning';
    if (level >= 800) return 'info';
    return 'debug';
  }

  // ---------------------------------------------------------------------------
  // Tool registration — delegates to category mixins
  // ---------------------------------------------------------------------------

  void _registerTools() {
    _registerAppInspectionTools();
    _registerUiAutomationTools();
    _registerNativeAutomationTools();
    // Hidden until a connection shows they can work (iOS + idb/xcrun).
    if (!staticTools) {
      for (final tool in _nativeTools.values) {
        tool.disable();
      }
      _allTools['run_on_devices']?.disable();
    }
    _registerNavigationTools();
    _registerScreenshotTools();
    _registerSelfHealTools();
    _registerStateManagementTools();
    _registerTestingTools();
    _registerDevtoolsTools();
    _registerTestGenerationTools();
    _registerScenarioTools();
    _registerVerificationTools();
    _registerPluginIntegrationTools();
  }

  /// Names of every registered tool, listed or not.
  Iterable<String> get registeredToolNames => _allTools.keys;

  /// Every registered tool's description, by name.
  Map<String, String> get toolDescriptions => {
    for (final MapEntry(key: name, value: tool) in _allTools.entries)
      name: tool.description ?? '',
  };

  /// The registered devices (tests add some without running apps).
  FleetManager get fleet => _fleetManager;

  /// Names of the tools currently listed to MCP clients.
  Iterable<String> get listedToolNames =>
      _allTools.entries.where((e) => e.value.enabled).map((e) => e.key);

  Timer? _visibilityTimer;

  /// Extensions arrive in bursts (~70 at startup, again after a hot
  /// restart): recompute once they settle.
  void _scheduleToolVisibility() {
    _visibilityTimer?.cancel();
    _visibilityTimer = Timer(
      const Duration(milliseconds: 300),
      _refreshToolVisibility,
    );
  }

  /// Reads which extensions the active app has registered and lists the tools
  /// that can work with them.
  @override
  Future<void> _refreshToolVisibility() async {
    final context = _activeContext;
    final vm = context?.service;
    if (context == null || vm == null || context.hasSdk == null) return;
    try {
      final rpcs = <String>{};
      for (final ref in (await vm.getVM()).isolates ?? const <IsolateRef>[]) {
        rpcs.addAll((await vm.getIsolate(ref.id!)).extensionRPCs ?? const []);
      }
      if (!identical(context, _activeContext)) return;
      updateToolVisibility(
        hasSdk: context.hasSdk,
        extensions: rpcs,
        buildMode: context.buildMode,
        isWeb: context.isWeb,
      );
    } catch (_) {
      // Keep the current list; calls explain themselves.
    }
  }

  /// Lists only the tools that can work: without flutterpilot_sdk in the app
  /// (zero-code mode) that is [zeroCodeTools]; with it, a plugin's tools once
  /// the app registers that plugin ([pluginToolExtensions]). Before the check
  /// ([hasSdk] null) everything. Profile builds drop [debugOnlyTools], web
  /// apps [webUnsupportedTools]; run_on_devices waits for a second
  /// registered device. Native tools keep their own rule. Sends one
  /// tools/list_changed instead of one per tool.
  void updateToolVisibility({
    required bool? hasSdk,
    Set<String> extensions = const {},
    BuildMode? buildMode,
    bool isWeb = false,
  }) {
    if (staticTools) return;
    var changed = false;
    for (final MapEntry(key: name, value: tool) in _allTools.entries) {
      if (_nativeTools.containsKey(name)) continue;
      final needs = pluginToolExtensions[name];
      final usable = switch (hasSdk) {
        // Comparing devices needs two of them.
        _ when name == 'run_on_devices' && _fleetManager.deviceIds.length < 2 =>
          false,
        // AOT: no hot reload, nor what is built on it.
        _
            when buildMode == BuildMode.profile &&
                debugOnlyTools.contains(name) =>
          false,
        _ when isWeb && webUnsupportedTools.contains(name) => false,
        false => zeroCodeTools.contains(name),
        true when needs != null => needs.any(extensions.contains),
        _ => true,
      };
      if (tool.enabled == usable) continue;
      changed = true;
      try {
        // Set the flag without mcp_dart's per-tool list_changed notification.
        (tool as dynamic).enabled = usable;
      } catch (_) {
        usable ? tool.enable() : tool.disable();
      }
    }
    if (changed) server.sendToolListChanged();
  }

  // ---------------------------------------------------------------------------
  // Prompts
  // ---------------------------------------------------------------------------

  void _registerPrompts() {
    server.registerPrompt(
      'flutterpilot_guide',
      title: 'FlutterPilot Usage Guide',
      description:
          'Complete guide on how to use FlutterPilot tools effectively. '
          'Call this prompt at the start of a session to understand all available tools, '
          'when to use each one, and recommended workflows.',
      callback: (args, extra) async {
        return GetPromptResult(
          description: 'FlutterPilot complete usage guide',
          messages: [
            PromptMessage(
              role: PromptMessageRole.user,
              content: TextContent(
                text: '''# FlutterPilot — AI Agent Guide

You are connected to a live Flutter app via FlutterPilot. Every tool
targets the active device (see list_connected_devices / switch_device);
run_on_devices runs the same steps on every registered device and compares.

## First steps
1. `get_app_summary` — route, tappable elements (labels + keys), errors, logs, window visibility
2. `capture_screenshot` — what the user sees
3. `get_widget_tree` — keys and structure (diff:true: only what changed)
4. `inspect_widget(key | x,y)` — the file:line in the app's code that draws a widget, and the app widgets above it

## Acting
- `tap_widget(key)` — key, `Type['text']` selector, exact visible text, or x/y; gesture: double / long / secondary; waitFor: a widget to wait for after the tap
- `enter_text(key, text)` — type into a field ("" clears it); `press_key("enter")` submits
- `press_key(key)` — enter/tab/escape/arrows/shortcuts; "back" = system back (never quits from the root)
- `fill_form(fields, submitWith)` — several fields (+ checkboxes) in one call
- `execute_action_chain(actions)` — a known sequence of taps/text in one call
- `scroll_into_view`, `swipe_widget`, `drag_widget`, `pinch_zoom`, `set_slider_value`, `toggle_checkbox`, `focus_widget`
- `navigate_to(route)` — jump to a route (action push/replace with go_router; deepLink:true)
Every action reports whether the route changed, a widget-tree diff and what is tappable now: read it before re-checking.

## Waiting and checking
- `wait_for(key | route | animations | state+expectedValue | frames)` — poll, never sleep
- `assert_widget(text | key [+enabled] | type+count)` — milliseconds, against the running app
- `compare_screenshot(name, save:true)` then `compare_screenshot(name)` — visual regression
- `audit_screen_health` — overflows and small tap targets (with `set_app_settings(textScale: 2)`)

## Reading state
- `get_errors` (report:true: full crash report), `get_debug_logs` (clear:true)
- `get_navigation_stack` — routes (go_router: params, routes:true, history:true)
- `get_state` / `set_state` — Riverpod and Bloc (plugins)
- `get_network_logs`, `mock_http_response`, `simulate_network` — Dio plugin
- `get_http_profile` — any dart:io client (clear:true for a baseline)
- storage: `exec_sql_query`, `get_shared_preferences`, `get_hive_contents`, `get_secure_storage`

## Changing how the app renders
- `set_app_settings` — theme, locale, textScale, orientation, debugPaint, repaintRainbow, slowAnimations

## Performance
- `profile_frame_budget` — p50/p90/p99 build/raster, jank
- `profile_action(tool, arguments)` — CPU profile of one action: the app functions it ran (self/total ms, file:line), and for janky frames build/layout/paint/raster and the app widgets that rebuilt
- `get_memory_details` (classes:true: top classes by heap) — compare before/after a screen for leaks

## Fixing
1. `get_errors` → your source frame (file:line)
2. edit the Dart source → `hot_reload` (restart:true for main()/static initializers/provider definitions)
3. repeat the steps; `assert_widget` / `get_errors` to confirm
''',
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Core helpers
  // ---------------------------------------------------------------------------

  @override
  void _registerAppTool({
    required String name,
    required String description,
    required String extension,
    Map<String, JsonSchema>? properties,
    String Function(Map<String, dynamic> json)? formatResult,
  }) {
    _tool(
      name,
      description: description,
      inputSchema: ToolInputSchema(properties: {...?properties}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(extension, p);
        if (res.isError) return res.toCallToolResult();
        final text = formatResult != null
            ? formatResult(res.data!)
            : jsonEncode(res.data);
        return CallToolResult(
          content: [TextContent(text: _boundToolText(text))],
        );
      },
    );
  }

  static String _boundToolText(String text) {
    final bytes = utf8.encode(text);
    if (bytes.length <= _Constants.maxToolResponseBytes) return text;
    return '${utf8.decode(bytes.take(_Constants.maxToolResponseBytes).toList(), allowMalformed: true)}\n[response truncated]';
  }

  @override
  CallToolResult _destructiveOperationDenied() => CallToolResult(
    content: [
      TextContent(
        text:
            'Destructive operation blocked. Restart FlutterPilot with --allow-destructive to enable app data mutation.',
      ),
    ],
    isError: true,
  );

  @override
  Future<_ExtensionResult> _callExtensionRaw(
    String extension,
    Map<String, dynamic> parameters,
  ) async {
    parameters = normalizeToolParams(parameters);
    if (extension.startsWith('ext.flutterpilot.')) await _sdkExtensionsReady;
    final context = await _deviceContextForParameters(parameters);
    final deviceId =
        context?.deviceId ?? _fleetManager.activeDeviceId ?? 'default';
    if (context == null || context.service == null) {
      return _ExtensionResult.error(
        _fleetManager.deviceIds.length > 1
            ? 'Device "$deviceId" is not running (app stopped, or restarted '
                  'on a new port). If it restarted, call register_device(id: '
                  '"$deviceId", uri: <new URI>); list_connected_devices shows '
                  'the others.'
            : 'No running Flutter app found. ${VmDiscoveryService.howToStart}',
        ErrorCategory.connectionLost,
      );
    }
    // iOS suspends a backgrounded app: every call would hang until it's back.
    if (context.lifecycle == 'paused' && context.operatingSystem == 'ios') {
      return _ExtensionResult.error(
        'The app is in the background, and iOS suspends it: nothing can '
        'reach it until it is in the foreground again. On the simulator call '
        'native_open_app; on a phone, open the app.',
        ErrorCategory.appInBackground,
      );
    }
    context.connectionGeneration = context.connectionGeneration == 0
        ? _connectionGeneration
        : context.connectionGeneration;
    return _callExtensionScheduled(extension, parameters, context);
  }

  @override
  Future<DeviceRuntimeContext?> _deviceContextForParameters(
    Map<String, dynamic> parameters,
  ) async {
    final pinned = Zone.current[_pinnedDevice] as String?;
    if (pinned != null && pinned != _fleetManager.activeDeviceId) {
      return _pinnedContext(pinned);
    }
    final deviceId = _fleetManager.activeDeviceId ?? 'default';
    if (_vmService == null) await _connectWithUri();
    if (_vmService == null) return _deviceContexts[deviceId];
    return (_deviceContexts[deviceId] ??= DeviceRuntimeContext(
      deviceId: deviceId,
      uri: _vmServiceUri ?? '',
    ))..service ??= _vmService;
  }

  /// A registered device other than the active one, on its own
  /// connection (run_on_devices drives several at once); the active
  /// device's connection and event streams are left alone.
  Future<DeviceRuntimeContext?> _pinnedContext(String id) async {
    final uri = _fleetManager.uriFor(id);
    if (uri == null) return null;
    final context = _deviceContexts[id] ??= DeviceRuntimeContext(
      deviceId: id,
      uri: uri,
    );
    if (context.service != null && context.uri == uri) return context;
    await context.dispose();
    context.uri = uri;
    VmService? service;
    try {
      service = await connectVmService(
        uri,
      ).timeout(_Constants.vmServiceTimeout);
      final vm = await service.getVM();
      context
        ..operatingSystem = vm.operatingSystem
        ..targetCPU = vm.targetCPU
        ..connectionGeneration = _connectionGeneration
        ..hasSdk = await _waitForSdkExtensions(service);
      try {
        context.buildMode = buildModeFromFlags(
          (await service.getFlagList()).flags ?? const [],
        );
      } catch (_) {}
      context.service = service;
    } catch (_) {
      // No service: the call says the device is not running.
      await service?.dispose();
    }
    return context;
  }

  @override
  Future<VmService?> _vmServiceForParameters(
    Map<String, dynamic> parameters,
  ) async => (await _deviceContextForParameters(parameters))?.service;

  Future<_ExtensionResult> _callExtensionScheduled(
    String extension,
    Map<String, dynamic> parameters,
    DeviceRuntimeContext context,
  ) async {
    final operationId = 'op-${++_nextOperationId}';
    final mutating = !_isReadOnlyExtension(extension);
    final generation = context.connectionGeneration;
    final scheduler = context.scheduler;

    _log.fine(
      '[$operationId] ${mutating ? 'mutation' : 'read'} $extension '
      '(device=${context.deviceId}, connection=${context.uri}, generation=$generation)',
    );

    final scheduled = scheduler.schedule(
      mutating: mutating,
      operation: () async {
        if (generation != context.connectionGeneration && generation != 0) {
          return _ExtensionResult.error(
            'The app connection changed while this call waited. Retry '
            'against the current device.',
            ErrorCategory.staleOperation,
          );
        }
        final result = await _callExtensionImmediate(
          extension,
          parameters,
          context: context,
        );
        if (generation != context.connectionGeneration && !result.isError) {
          return _ExtensionResult.error(
            'The app connection changed while this call ran. Retry against '
            'the current device.',
            ErrorCategory.staleOperation,
          );
        }
        return result;
      },
    );
    return scheduled.timeout(
      _operationDeadline,
      onTimeout: () => _ExtensionResult.error(
        'No answer from the app within ${_operationDeadline.inSeconds} s. '
        'Check the app state before retrying: a change may still apply.',
        ErrorCategory.deadlineExceeded,
      ),
    );
  }

  static const _operationDeadline = Duration(seconds: 30);

  static bool _isReadOnlyExtension(String extension) {
    return extension.startsWith('ext.flutterpilot.get') ||
        extension.startsWith('ext.flutterpilot.list') ||
        extension.startsWith('ext.flutterpilot.wait') ||
        extension.startsWith('ext.flutterpilot.assert') ||
        extension.startsWith('ext.flutterpilot.capture') ||
        extension.startsWith('ext.flutterpilot.compare') ||
        extension.startsWith('ext.flutterpilot.diagnose') ||
        extension.startsWith('ext.flutterpilot.audit') ||
        extension.startsWith('ext.flutterpilot.profile') ||
        extension.startsWith('ext.flutterpilot.query') ||
        extension.startsWith('ext.flutterpilot.export') ||
        extension.startsWith('ext.flutterpilot.generate') ||
        extension.startsWith('ext.flutterpilot.ping') ||
        extension.startsWith('ext.dart.io.get') ||
        extension == 'ext.flutter.inspector.getRootWidgetTree';
  }

  void _markContextConnectionLost(DeviceRuntimeContext? context) {
    if (context == null) {
      _scheduleReconnect();
      return;
    }
    context.service = null;
    context.cachedMainIsolateId = null;
    context.connectionGeneration++;
    if (context.deviceId == _fleetManager.activeDeviceId) {
      _vmService = null;
      _scheduleReconnect();
    }
  }

  final Map<String, String> _appRootByIsolate = {};

  /// Tells the SDK where the app's own code lives, so it can tell app widgets
  /// from framework/package widgets (the DevTools "summary tree" rule). Taken
  /// from the isolate's root library, not from where this server was started.
  Future<Map<String, String>> _withAppRoot(
    VmService vm,
    String isolateId,
    String extension,
    Map<String, String> args,
  ) async {
    if (!extension.startsWith('ext.flutterpilot.')) return args;
    var root = _appRootByIsolate[isolateId];
    if (root == null) {
      var resolved = _projectRoot.absolute.path;
      try {
        var uri = (await vm.getIsolate(isolateId)).rootLib?.uri;
        if (uri != null && uri.startsWith('package:')) {
          uri = (await vm.lookupResolvedPackageUris(isolateId, [
            uri,
          ])).uris?.first;
        }
        if (uri != null && uri.startsWith('file:')) {
          final path = Uri.parse(uri).path;
          final lib = path.lastIndexOf('/lib/');
          if (lib > 0) resolved = path.substring(0, lib);
        }
      } catch (_) {}
      root = _appRootByIsolate[isolateId] = resolved;
    }
    return {...args, 'projectRoot': root};
  }

  /// Runs [extension] once; if the VM service connection drops mid-call
  /// (slow simulators do this), reconnects. Reads are retried; actions are
  /// not — they may already have run — and say so instead.
  Future<_ExtensionResult> _callExtensionImmediate(
    String extension,
    Map<String, dynamic> parameters, {
    DeviceRuntimeContext? context,
  }) async {
    final result = await _callExtensionImmediateOnce(
      extension,
      parameters,
      context: context,
    );
    final message = result.errorMessage ?? '';
    final dropped =
        message.contains('Service connection disposed') ||
        message.contains('Service has disappeared');
    if (!dropped) return result;

    _markContextConnectionLost(context);
    try {
      await _connectToVmService();
    } catch (_) {}
    if (_isReadOnlyExtension(extension) && _vmService != null) {
      return _callExtensionImmediateOnce(
        extension,
        parameters,
        context: context,
      );
    }
    return _ExtensionResult.error(
      'The connection to the app dropped during this call (reconnected: '
      '${_vmService != null}). The action may or may not have run — check '
      'with get_app_summary before retrying.',
      ErrorCategory.connectionLost,
    );
  }

  Future<_ExtensionResult> _callExtensionImmediateOnce(
    String extension,
    Map<String, dynamic> parameters, {
    DeviceRuntimeContext? context,
  }) async {
    final vmService = context?.service ?? _vmService;
    // The global cache is the active device's isolate, not another one's.
    String? cachedIsolateId =
        context?.cachedMainIsolateId ??
        (context == null || identical(context, _activeContext)
            ? _cachedMainIsolateId
            : null);
    void cacheIsolate(String? isolateId) {
      if (context != null) {
        context.cachedMainIsolateId = isolateId;
      } else {
        _cachedMainIsolateId = isolateId;
      }
      cachedIsolateId = isolateId;
    }

    if (vmService == null) {
      // Attempt quick auto-connect if disconnected
      await _connectWithUri();
      if (_vmService == null) {
        if (_isReconnecting) {
          return _ExtensionResult.error(
            'VM Service is reconnecting. Please retry shortly.',
            ErrorCategory.reconnecting,
          );
        }
        return _ExtensionResult.error(
          'No active Flutter app connection. Start your app with "flutter run" or call connect_app(uri: "...") to connect.',
          ErrorCategory.connectionLost,
        );
      }
    }
    final stringArgs = parameters is Map<String, String>
        ? parameters
        : {for (final e in parameters.entries) e.key: e.value.toString()};
    // An action is sent once: when the app is slow to answer (a first text
    // entry on a CI simulator took 18 s), sending it again would tap or type
    // twice. It gets the whole operation deadline instead. A read is asked
    // again after the shorter timeout.
    final readOnly = _isReadOnlyExtension(extension);
    final callTimeout = readOnly
        ? _Constants.extensionCallTimeout
        : _operationDeadline;
    final actionTimedOut = _ExtensionResult.error(
      'No answer from the app within ${callTimeout.inSeconds} s. The action '
      'may or may not have run — check with get_app_summary before retrying.',
      ErrorCategory.timeout,
    );

    // Fast-path: use cached isolate ID if available
    if (cachedIsolateId != null) {
      try {
        final response = await vmService!
            .callServiceExtension(
              extension,
              isolateId: cachedIsolateId!,
              args: await _withAppRoot(
                vmService,
                cachedIsolateId!,
                extension,
                stringArgs,
              ),
            )
            .timeout(callTimeout);
        if (response.json != null) {
          if (response.json!['error'] != null) {
            return _ExtensionResult.error(
              'Error: ${response.json!['error']}',
              ErrorCategory.extensionError,
            );
          }
          return _ExtensionResult.success(response.json!);
        }
      } on RPCError catch (e) {
        if (e.code == -32601) {
          final fallback = await _handleZeroCodeFallback(
            extension,
            parameters,
            cachedIsolateId!,
            context: context,
          );
          if (fallback != null) return fallback;
        } else if (e.code == 105 || e.message.contains('Isolate')) {
          cacheIsolate(null);
        } else {
          return _ExtensionResult.error(
            e.data?['details'] as String? ?? 'Extension error: ${e.message}',
            ErrorCategory.extensionError,
          );
        }
      } on TimeoutException {
        if (!readOnly) return actionTimedOut;
        // Fall back to full isolate refresh
      } catch (e) {
        _log.fine(
          'Unexpected error calling extension on cached isolate, clearing cache: $e',
        );
        cacheIsolate(null);
      }
    }

    try {
      final vm = await vmService!.getVM().timeout(_Constants.vmServiceTimeout);
      for (final isolateRef in vm.isolates ?? []) {
        if (isolateRef.id == null) continue;
        try {
          final response = await vmService
              .callServiceExtension(
                extension,
                isolateId: isolateRef.id!,
                args: await _withAppRoot(
                  vmService,
                  isolateRef.id!,
                  extension,
                  stringArgs,
                ),
              )
              .timeout(callTimeout);
          if (response.json != null) {
            if (response.json!['error'] != null) {
              return _ExtensionResult.error(
                'Error: ${response.json!['error']}',
                ErrorCategory.extensionError,
              );
            }
            cacheIsolate(isolateRef.id);
            return _ExtensionResult.success(response.json!);
          }
        } on RPCError catch (e) {
          if (e.code == -32601) {
            final fallback = await _handleZeroCodeFallback(
              extension,
              parameters,
              isolateRef.id!,
              context: context,
            );
            if (fallback != null) return fallback;
            continue;
          }
          return _ExtensionResult.error(
            e.data?['details'] as String? ?? 'Extension error: ${e.message}',
            ErrorCategory.extensionError,
          );
        } on TimeoutException {
          if (!readOnly) return actionTimedOut;
          return _ExtensionResult.error(
            'Extension call timed out. The app may be unresponsive.',
            ErrorCategory.timeout,
          );
        }
      }
      if (extension.startsWith('ext.dart.io.') && context?.isWeb == true) {
        return _ExtensionResult.error(
          'Extension "$extension" is not available on web: web apps use browser networking rather than dart:io.',
          ErrorCategory.extensionError,
        );
      }
      return _ExtensionResult.error(
        'Extension "$extension" is not registered in the running Flutter app. '
        'Plugin extensions register only once the app runs the plugin\'s setup code '
        '(e.g. the first `Dio()` with DioPilotInterceptor is created). If the package is lazily '
        'created, trigger that code path first, or wire the plugin in main(). '
        'If the plugin is not installed at all, run "flutterpilot init".',
        ErrorCategory.extensionError,
      );
    } on TimeoutException {
      return _ExtensionResult.error(
        'VM Service timed out. The app may be unresponsive.',
        ErrorCategory.timeout,
      );
    } on StateError catch (e) {
      _log.warning('VM Service connection error during call', e);
      _markContextConnectionLost(context);
      return _ExtensionResult.error(
        'VM Service connection lost. Reconnecting...',
        ErrorCategory.connectionLost,
      );
    } on WebSocketException catch (e) {
      _log.warning('WebSocket error during VM Service call', e);
      _markContextConnectionLost(context);
      return _ExtensionResult.error(
        'VM Service connection lost. Reconnecting...',
        ErrorCategory.connectionLost,
      );
    } on IOException catch (e) {
      _log.warning('IO error during VM Service call', e);
      _markContextConnectionLost(context);
      return _ExtensionResult.error(
        'VM Service connection lost. Reconnecting...',
        ErrorCategory.connectionLost,
      );
    }
  }

  /// The app has no handler for [extension]. Without flutterpilot_sdk
  /// (zero-code mode) answer what Flutter's own inspector can, and say
  /// plainly that the rest needs the SDK. Returns null when the SDK is
  /// installed: then the missing extension belongs to a plugin.
  Future<_ExtensionResult?> _handleZeroCodeFallback(
    String extension,
    Map<String, dynamic> parameters,
    String isolateId, {
    DeviceRuntimeContext? context,
  }) async {
    context ??= _deviceContexts[_fleetManager.activeDeviceId ?? 'default'];
    final vmService = context?.service ?? _vmService;
    if (vmService == null || !extension.startsWith('ext.flutterpilot.')) {
      return null;
    }
    var hasSdk = context?.hasSdk;
    if (hasSdk == null) {
      final rpcs = (await vmService.getIsolate(isolateId)).extensionRPCs;
      hasSdk = rpcs?.any((e) => e.startsWith('ext.flutterpilot.')) ?? false;
    }
    if (hasSdk) return null;

    var usedInspector = false;
    Future<Map<String, dynamic>?> inspectorRoot() async {
      usedInspector = true;
      final res = await vmService.callServiceExtension(
        'ext.flutter.inspector.getRootWidgetTree',
        isolateId: isolateId,
        args: {
          'groupName': _inspectorGroup,
          'isSummaryTree': 'false',
          'withPreviews': 'true',
        },
      );
      return (res.json?['result'] as Map?)?.cast<String, dynamic>();
    }

    Future<List<Map>> properties(String id) async {
      final res = await vmService.callServiceExtension(
        'ext.flutter.inspector.getProperties',
        isolateId: isolateId,
        args: {'objectGroup': _inspectorGroup, 'arg': id},
      );
      return (res.json?['result'] as List? ?? const [])
          .whereType<Map>()
          .toList();
    }

    Map? property(List<Map> props, String name) =>
        props.where((p) => p['name'] == name).firstOrNull;

    /// What keeps children off screen: skipped overlay entries (covered
    /// routes) per `_Theater`, the painted child per IndexedStack.
    Future<({Map<String, int> skip, Map<String, int> index})> offstage(
      Map<String, dynamic> root,
    ) async {
      final hosts = offstageHosts(root);
      final skip = await Future.wait(
        hosts.theaters.map((id) async {
          final count = property(await properties(id), 'skipCount');
          return MapEntry(id, int.tryParse('${count?['description']}') ?? 0);
        }),
      );
      final index = await Future.wait(
        hosts.indexedStacks.map((id) async {
          final ro = property(await properties(id), 'renderObject');
          final roId = ro?['valueId']?.toString();
          if (roId == null) return null;
          final i = property(await properties(roId), 'index');
          final value = int.tryParse('${i?['description']}');
          return value == null ? null : MapEntry(id, value);
        }),
      );
      return (
        skip: Map.fromEntries(skip),
        index: Map.fromEntries(index.nonNulls),
      );
    }

    try {
      switch (extension) {
        case 'ext.flutterpilot.getWidgetTree':
        case 'ext.flutterpilot.getSummary':
          final root = await inspectorRoot();
          if (root == null) {
            return _ExtensionResult.error(
              'The Flutter inspector returned no widget tree (the first frame '
              'may not be built yet). Retry in a moment.',
              ErrorCategory.extensionError,
            );
          }
          final maxDepth = int.tryParse('${parameters['maxDepth']}') ?? 50;
          final hidden = await offstage(root);
          final tree = summaryTreeFromInspector(
            root,
            maxDepth: maxDepth,
            skipCounts: hidden.skip,
            stackIndexes: hidden.index,
          );
          if (extension == 'ext.flutterpilot.getWidgetTree') {
            return _ExtensionResult.success({
              'sdkMode': 'zero-code',
              'tree': tree,
            });
          }
          final vm = await vmService.getVM();
          final memory = await vmService.getMemoryUsage(isolateId);
          final content = screenContent(tree);
          return _ExtensionResult.success({
            'sdkMode': 'zero-code',
            'flutterVersion': vm.version ?? 'unknown',
            'heapUsageMb': ((memory.heapUsage ?? 0) / (1024 * 1024)).round(),
            'texts': content.texts,
            'keys': content.keys,
            'errors': context?.zeroCodeErrors ?? const [],
          });
        case 'ext.flutterpilot.captureScreenshot':
          usedInspector = true;
          final rootWidget = await vmService.callServiceExtension(
            'ext.flutter.inspector.getRootWidget',
            isolateId: isolateId,
            args: {'objectGroup': _inspectorGroup},
          );
          final id = (rootWidget.json?['result'] as Map?)?['valueId'];
          if (id == null) {
            return _ExtensionResult.error(
              'The Flutter inspector returned no widget tree (the first frame '
              'may not be built yet). Retry in a moment.',
              ErrorCategory.extensionError,
            );
          }
          final layout = await vmService.callServiceExtension(
            'ext.flutter.inspector.getLayoutExplorerNode',
            isolateId: isolateId,
            args: {'groupName': _inspectorGroup, 'id': id, 'subtreeDepth': '0'},
          );
          final size = (layout.json?['result'] as Map?)?['size'] as Map?;
          // Like the SDK: logical pixels x scale.
          final pixelRatio = double.tryParse('${parameters['scale']}') ?? 1.0;
          final res = await vmService.callServiceExtension(
            'ext.flutter.inspector.screenshot',
            isolateId: isolateId,
            args: {
              'id': id,
              'width': '100000',
              'height': '100000',
              'maxPixelRatio': '$pixelRatio',
            },
          );
          final data = res.json?['result'];
          if (data is! String) {
            return _ExtensionResult.error(
              'The Flutter inspector returned no screenshot (the first frame '
              'may not be built yet). Retry in a moment.',
              ErrorCategory.extensionError,
            );
          }
          final width = double.tryParse('${size?['width']}');
          final height = double.tryParse('${size?['height']}');
          return _ExtensionResult.success({
            'data': width == null || height == null
                ? data
                : cropToScreen(data, width, height, pixelRatio),
          });
        case 'ext.flutterpilot.getErrors':
          return _ExtensionResult.success({
            'sdkMode': 'zero-code',
            'errors': context?.zeroCodeErrors ?? const [],
          });
      }
    } catch (e) {
      return _ExtensionResult.error(
        'Zero-code mode (no flutterpilot_sdk): the Flutter inspector call '
        'failed: $e',
        ErrorCategory.extensionError,
      );
    } finally {
      if (usedInspector) {
        unawaited(
          vmService
              .callServiceExtension(
                'ext.flutter.inspector.disposeGroup',
                isolateId: isolateId,
                args: {'objectGroup': _inspectorGroup},
              )
              .then<void>((_) {}, onError: (_) {}),
        );
      }
    }
    return _ExtensionResult.error(
      zeroCodeUnavailable('This tool'),
      ErrorCategory.toolNotFound,
    );
  }

  static const _inspectorGroup = 'flutterpilot-zero-code';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> stop() async {
    _disposed = true;
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _visibilityTimer?.cancel();
    for (final context in _deviceContexts.values) {
      await context.dispose();
    }
    _deviceContexts.clear();
    _vmService = null;
  }
}

// ---------------------------------------------------------------------------
// Internal DTO for VM extension call results
// ---------------------------------------------------------------------------

/// Category of error returned by a tool call, enabling AI agents to decide
/// whether to retry, call a different tool, or report the failure.
enum ErrorCategory {
  /// The VM Service connection is not available.
  connectionLost,

  /// The app is backgrounded and suspended by the OS (iOS).
  appInBackground,

  /// The VM Service is currently reconnecting — retry shortly.
  reconnecting,

  /// The extension call timed out (app may be unresponsive).
  timeout,

  /// The requested extension was not found in any isolate.
  toolNotFound,

  /// The extension returned an application-level error.
  extensionError,

  /// Input validation failed (missing/invalid parameters).
  validation,

  /// The operation was queued for an older device connection or isolate.
  staleOperation,

  /// The server-side operation deadline elapsed before completion.
  deadlineExceeded,
}

class _ExtensionResult {
  final Map<String, dynamic>? data;
  final String? errorMessage;
  final bool isError;
  final ErrorCategory? errorCategory;
  _ExtensionResult.success(this.data)
    : errorMessage = null,
      isError = false,
      errorCategory = null;
  _ExtensionResult.error(this.errorMessage, [this.errorCategory])
    : data = null,
      isError = true;

  CallToolResult toCallToolResult() {
    final message = isError
        ? (errorCategory != null
              ? '[${errorCategory!.name}] ${errorMessage ?? 'Unknown error'}'
              : (errorMessage ?? 'Unknown error'))
        : jsonEncode(data ?? {});
    return CallToolResult(
      content: [TextContent(text: FlutterPilotServer._boundToolText(message))],
      isError: isError,
    );
  }
}
