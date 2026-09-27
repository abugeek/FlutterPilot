part of '../../flutterpilot_server.dart';

/// Tools for inspecting application state, errors, events, config, and logs.
mixin _AppInspectionToolsMixin on _FlutterPilotServerBase {
  String get _activeDeviceId => _fleetManager.activeDeviceId ?? 'default';

  List<Map<String, dynamic>> get _activeDebugLogs => _debugLogBuffer
      .where((entry) => (entry['deviceId'] ?? 'default') == _activeDeviceId)
      .toList();

  List<Map<String, dynamic>> get _activeEvents => _eventBuffer
      .where((entry) => (entry['deviceId'] ?? 'default') == _activeDeviceId)
      .toList();

  void _registerAppInspectionTools() {
    _tool(
      'get_operation',
      description:
          'Polls an asynchronous operation submitted with async:true. '
          'Returns pending, completed, or failed status.',
      inputSchema: ToolInputSchema(
        properties: {
          'operationId': JsonSchema.string(
            description: 'The operation ID returned by the async submission.',
          ),
        },
        required: ['operationId'],
      ),
      callback: (params, extra) async {
        final operationId = params['operationId'] as String?;
        if (operationId == null || operationId.isEmpty) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Missing operationId.')],
          );
        }
        final operation = _getBackgroundOperation(operationId);
        if (operation == null) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(text: 'Unknown or expired operation $operationId.'),
            ],
          );
        }
        final result = operation.result;
        if (result == null) {
          return CallToolResult(
            content: [
              TextContent(
                text: jsonEncode({
                  'status': 'pending',
                  'operationId': operationId,
                }),
              ),
            ],
          );
        }
        return result.toCallToolResult();
      },
    );

    _tool(
      'cancel_operation',
      description:
          'Cancels a queued FlutterPilot operation before it starts. '
          'Already-running VM calls are allowed to finish safely.',
      inputSchema: ToolInputSchema(
        properties: {
          'operationId': JsonSchema.string(
            description: 'The operation ID returned by the original tool call.',
          ),
        },
        required: ['operationId'],
      ),
      callback: (params, extra) async {
        final operationId = params['operationId'] as String?;
        if (operationId == null || operationId.isEmpty) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Missing operationId.')],
          );
        }
        final cancelled = _cancelOperation(operationId);
        return CallToolResult(
          isError: !cancelled,
          content: [
            TextContent(
              text: cancelled
                  ? 'Cancelled queued operation $operationId.'
                  : 'Operation $operationId was not queued or has already started.',
            ),
          ],
        );
      },
    );

    _tool(
      'connect_app',
      description:
          'Connects or reconnects FlutterPilot to a running Flutter application. '
          'If uri is omitted, it automatically scans localhost for an active Flutter debug session.',
      inputSchema: ToolInputSchema(
        properties: {
          'uri': JsonSchema.string(
            description:
                'Optional VM Service URI (e.g. "http://127.0.0.1:12345/abcdefg=/"). If omitted, auto-discovers.',
          ),
        },
      ),
      callback: (params, extra) async {
        final uri = params['uri'] as String?;
        final success = await _connectWithUri(uri);
        if (success) {
          final connected = _connectedUri!;
          final info = await probeDevice(
            connected,
          ).then<Object>((i) => i, onError: (_) => 'Flutter app');
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Connected to $info at ${FleetManager.shortUri(connected)}.',
              ),
            ],
          );
        } else {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    '❌ Could not connect to a running Flutter app. Ensure your Flutter app is running in debug mode ("flutter run") and try again.',
              ),
            ],
          );
        }
      },
    );

    _tool(
      'list_connected_devices',
      description:
          'Lists the Flutter apps FlutterPilot knows (one per device: iOS, '
          'Android, web, desktop): platform, app, whether it runs '
          'flutterpilot_sdk, and which one is active. Every tool targets the '
          'active device.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final ids = _fleetManager.deviceIds.toList();
        final probes = await Future.wait(
          ids.map(
            (id) => probeDevice(
              _fleetManager.uriFor(id)!,
              timeout: const Duration(seconds: 2),
            ).then<DeviceInfo?>((info) => info, onError: (_) => null),
          ),
        );
        return CallToolResult(
          content: [
            TextContent(
              text: _fleetManager.describe({
                for (var i = 0; i < ids.length; i++) ids[i]: probes[i],
              }),
            ),
          ],
        );
      },
    );

    _tool(
      'register_device',
      description:
          'Adds a running Flutter app to the fleet under a name, e.g. the same '
          'app on an iPhone simulator next to the one on Android. Pass the VM '
          'service URI that flutter run prints ("A Dart VM Service on ... is '
          'available at: http://127.0.0.1:PORT/TOKEN=/"). Registering an '
          'existing name again updates its URI after the app restarted.',
      inputSchema: ToolInputSchema(
        properties: {
          'id': JsonSchema.string(
            description: 'A short name, e.g. "iphone", "pixel", "web".',
          ),
          'uri': JsonSchema.string(
            description:
                'The VM service URI (http://… as flutter run prints it, or ws://…/ws).',
          ),
        },
        required: ['id', 'uri'],
      ),
      callback: (p, e) async {
        final id = p['id'].toString().trim();
        final uri = normalizeVmServiceUri(p['uri'].toString());
        CallToolResult error(String text) =>
            CallToolResult(isError: true, content: [TextContent(text: text)]);
        if (id.isEmpty) return error('id must not be empty.');
        if (uri == null) {
          return error(
            '"${p['uri']}" is not a VM service URI. flutter run prints it as '
            '"A Dart VM Service on <device> is available at: '
            'http://127.0.0.1:<port>/<token>=/".',
          );
        }
        if (!_isAllowedConnectionUri(uri)) {
          return error(
            'Refusing a remote VM service URI; restart FlutterPilot with '
            '--allow-remote to connect to other hosts.',
          );
        }
        final DeviceInfo info;
        try {
          info = await probeDevice(uri);
        } catch (_) {
          return error(
            'No Flutter app answers at ${FleetManager.shortUri(uri)}. Is it '
            'still running? Nothing was registered.',
          );
        }
        final previous = _fleetManager.registerDevice(id, uri);
        if (previous != null) await _renameDeviceContext(previous, id);
        final active = _fleetManager.activeDeviceId;
        // Connect when this is now the active device (the first one, or the
        // active one re-registered after a restart).
        if (active == id && (_vmService == null || _connectedUri != uri)) {
          await _connectWithUri(uri);
        }
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Registered "$id": $info.${previous != null ? ' (Was listed as "$previous".)' : ''} '
                  '${active == id ? 'It is the active device.' : 'Active device: "$active"; call switch_device(id: "$id") to target it.'}',
            ),
          ],
        );
      },
    );

    _tool(
      'switch_device',
      description:
          'Makes a registered device the active one: every tool call after '
          'this targets it. See list_connected_devices for the names.',
      inputSchema: ToolInputSchema(
        properties: {
          'id': JsonSchema.string(
            description: 'The name of a registered device.',
          ),
        },
        required: ['id'],
      ),
      callback: (p, e) async {
        final id = p['id'].toString();
        final active = _fleetManager.activeDeviceId;
        CallToolResult error(String text) =>
            CallToolResult(isError: true, content: [TextContent(text: text)]);
        final uri = _fleetManager.uriFor(id);
        if (uri == null) {
          return error(
            'No device "$id". Registered: '
            '${_fleetManager.deviceIds.map((d) => '"$d"').join(', ')}.',
          );
        }
        final DeviceInfo info;
        try {
          info = await probeDevice(uri);
        } catch (_) {
          return error(
            'Device "$id" is not running at ${FleetManager.shortUri(uri)} '
            '(app stopped, or restarted on a new port). Still on "$active". '
            'If it restarted, call register_device(id: "$id", uri: <new URI>).',
          );
        }
        if (id == active && _vmService != null && _connectedUri == uri) {
          return CallToolResult(
            content: [TextContent(text: 'Already on "$id": $info.')],
          );
        }
        _fleetManager.switchDevice(id);
        if (!await _connectWithUri(uri)) {
          if (active != null) {
            _fleetManager.switchDevice(active);
            await _connectWithUri(_fleetManager.uriFor(active));
          }
          return error(
            'Could not connect to "$id" (${FleetManager.shortUri(uri)}). '
            'Still on "$active".',
          );
        }
        return CallToolResult(
          content: [
            TextContent(
              text: 'Switched to "$id": $info. Every tool now targets it.',
            ),
          ],
        );
      },
    );

    _registerAppTool(
      name: 'get_errors',
      description:
          'Retrieve the most recent unhandled exceptions and stack traces with duplicate aggregation. CALL THIS whenever you suspect a crash or logic failure.',
      extension: 'ext.flutterpilot.getErrors',
      formatResult: (json) {
        final errors = json['errors'] as List?;
        if (errors == null || errors.isEmpty) {
          return json['sdkMode'] == 'zero-code'
              ? 'No errors since FlutterPilot connected. Without '
                    'flutterpilot_sdk, earlier errors are not recorded; '
                    'hot_reload re-runs layout and reports layout errors that '
                    'still occur. On web, errors only reach get_debug_logs.'
              : 'No recent errors found.';
        }

        // Deduplicate identical errors
        final Map<String, Map<String, dynamic>> deduped = {};
        for (final item in errors) {
          if (item is Map) {
            final key = item['exception']?.toString() ?? 'unknown';
            if (!deduped.containsKey(key)) {
              deduped[key] = {
                'exception': key,
                'count': 1,
                'timestamp': item['timestamp'],
                'stackTrace': item['stackTrace'],
                'widget': item['widget'],
              };
            } else {
              deduped[key]!['count'] = (deduped[key]!['count'] as int) + 1;
              deduped[key]!['timestamp'] = item['timestamp'];
            }
          }
        }

        return deduped.values
            .map(
              (e) =>
                  '--- Error (x${e['count']}) ---\n${e['exception']}\n'
                  '${e['widget'] != null ? 'Widget: ${e['widget']}\n' : ''}'
                  'Latest: ${e['timestamp']}\n${e['stackTrace'] ?? ''}',
            )
            .join('\n\n');
      },
      nudge:
          'HINT: Analyze the stack trace to find the failing file, then use get_widget_tree to see the state of the UI at failure.',
    );

    _tool(
      'get_recent_events',
      description:
          'Retrieves all buffered proactive events (up to 50: errors, taps, state changes) from the stream. Use this to catch up on what happened while you were processing or if the user interacted with the app manually.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final activeEvents = _activeEvents;
        if (activeEvents.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'No recent events.')],
          );
        }
        return CallToolResult(
          content: [
            TextContent(
              text: activeEvents
                  .map(
                    (ev) => '[${ev['timestamp']}] ${ev['type']}: ${ev['data']}',
                  )
                  .join('\n'),
            ),
          ],
        );
      },
    );

    _tool(
      'get_build_config',
      description:
          'Reads the project\'s pubspec.yaml and returns the app name, '
          'version, Flutter/Dart SDK constraints, and dependency list. '
          'Use this to understand what packages are available before '
          'suggesting code that requires them.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final pubspec = File(
          '${_projectRoot.path}${Platform.pathSeparator}pubspec.yaml',
        );
        if (!await pubspec.exists()) {
          return CallToolResult(
            content: [TextContent(text: 'pubspec.yaml not found.')],
            isError: true,
          );
        }
        final content = await pubspec.readAsString();
        return CallToolResult(content: [TextContent(text: content)]);
      },
    );

    _tool(
      'read_dart_file',
      description:
          'Reads a Dart source file from the connected Flutter project. '
          'The path is relative to the project root (where pubspec.yaml is). '
          'Use this to give the AI agent codebase context: read widgets, '
          'models, routes, or test files before making changes.',
      inputSchema: ToolInputSchema(
        properties: {
          'path': JsonSchema.string(
            description:
                'Relative or absolute path to the Dart file. Relative paths resolve from the project root.',
          ),
        },
        required: ['path'],
      ),
      callback: (p, e) async {
        final pathParam = p['path'] as String?;
        if (pathParam == null || pathParam.trim().isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'path parameter is required')],
            isError: true,
          );
        }
        final relativePath = pathParam.toString();
        // Block absolute paths
        if (path.isAbsolute(relativePath)) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Error: absolute paths are not allowed. Use paths relative to project root.',
              ),
            ],
            isError: true,
          );
        }
        // Resolve symlinks and verify the path stays within the project
        final file = File(
          '${_projectRoot.path}${Platform.pathSeparator}$relativePath',
        );
        if (!await file.exists()) {
          return CallToolResult(
            content: [TextContent(text: 'File not found: $relativePath')],
            isError: true,
          );
        }
        try {
          final resolved = file.resolveSymbolicLinksSync();
          final projectCanonical = _projectRoot.resolveSymbolicLinksSync();
          final relative = path.relative(resolved, from: projectCanonical);
          if (relative == '..' ||
              relative.startsWith('..${Platform.pathSeparator}')) {
            return CallToolResult(
              content: [
                TextContent(
                  text: 'Error: path must be within the project directory.',
                ),
              ],
              isError: true,
            );
          }
        } catch (e) {
          _log.fine('Path resolution failed: $e');
          return CallToolResult(
            content: [TextContent(text: 'Error: unable to resolve path.')],
            isError: true,
          );
        }
        final content = await file.readAsString();
        return CallToolResult(content: [TextContent(text: content)]);
      },
    );

    _tool(
      'list_dart_files',
      description:
          'Lists all .dart files in the Flutter project under the given '
          'directory (defaults to "lib"). Returns relative paths from the '
          'project root. Use to explore project structure before reading files.',
      inputSchema: ToolInputSchema(
        properties: {
          'directory': JsonSchema.string(
            description:
                'Subdirectory to search for Dart files (e.g. "lib", "test"). Defaults to project root if omitted.',
          ),
        },
      ),
      callback: (p, e) async {
        final rawDir = p['directory']?.toString() ?? 'lib';
        // Block absolute paths
        if (path.isAbsolute(rawDir)) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Error: absolute paths are not allowed. Use relative paths.',
              ),
            ],
            isError: true,
          );
        }
        final searchDir = Directory(
          '${_projectRoot.path}${Platform.pathSeparator}$rawDir',
        );
        if (!await searchDir.exists()) {
          return CallToolResult(
            content: [TextContent(text: 'Directory not found: $rawDir')],
            isError: true,
          );
        }
        // Verify resolved path stays within project root
        try {
          final resolved = searchDir.resolveSymbolicLinksSync();
          final projectCanonical = _projectRoot.resolveSymbolicLinksSync();
          if (!resolved.startsWith(projectCanonical)) {
            return CallToolResult(
              content: [
                TextContent(
                  text: 'Error: path must be within the project directory.',
                ),
              ],
              isError: true,
            );
          }
        } catch (e) {
          return CallToolResult(
            content: [TextContent(text: 'Error: unable to resolve path.')],
            isError: true,
          );
        }
        final files = <String>[];
        await for (final entity in searchDir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            final relative = entity.path
                .replaceFirst(_projectRoot.path, '')
                .replaceFirst(RegExp(r'^[/\\]'), '');
            files.add(relative);
          }
        }
        files.sort();
        return CallToolResult(content: [TextContent(text: files.join('\n'))]);
      },
    );

    // -- get_logs / get_debug_logs --------------------------------------------
    Future<CallToolResult> executeGetLogs(Map<String, dynamic> params) async {
      final levelFilter = params['level'] as String?;
      final loggerFilter = params['logger'] as String?;
      final query = (params['query'] ?? params['search'])
          ?.toString()
          .toLowerCase();
      final sinceSeconds = (params['since_seconds'] as num?)?.toInt();
      final rawLimit = (params['limit'] as int?) ?? 100;
      final limit = rawLimit.clamp(1, _Constants.debugLogBufferMax);

      var entries = _activeDebugLogs;
      if (levelFilter != null && levelFilter.isNotEmpty) {
        entries = entries.where((e) => e['level'] == levelFilter).toList();
      }
      if (loggerFilter != null && loggerFilter.isNotEmpty) {
        entries = entries
            .where(
              (e) => (e['logger'] as String?)?.contains(loggerFilter) ?? false,
            )
            .toList();
      }
      if (query != null && query.isNotEmpty) {
        entries = entries
            .where(
              (e) =>
                  (e['message']?.toString().toLowerCase().contains(query) ??
                      false) ||
                  (e['logger']?.toString().toLowerCase().contains(query) ??
                      false),
            )
            .toList();
      }
      if (sinceSeconds != null && sinceSeconds > 0) {
        final cutoff = DateTime.now().subtract(Duration(seconds: sinceSeconds));
        entries = entries.where((e) {
          final t = DateTime.tryParse(e['timestamp']?.toString() ?? '');
          return t != null && t.isAfter(cutoff);
        }).toList();
      }
      if (entries.length > limit) {
        entries = entries.sublist(entries.length - limit);
      }
      if (entries.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'No console logs matching the filter since FlutterPilot '
                  'connected (print, debugPrint and dart:developer log output '
                  'is captured from then on).',
            ),
          ],
        );
      }
      final compacted = <String>[];
      String? prevMessage;
      String? prevLevel;
      String? prevLogger;
      String? prevTime;
      int repeatCount = 0;

      void flushPrevious() {
        if (prevMessage != null) {
          final loggerPrefix = (prevLogger != null && prevLogger.isNotEmpty)
              ? '($prevLogger) '
              : '';
          final repeatSuffix = repeatCount > 1
              ? ' [x$repeatCount occurrences]'
              : '';
          compacted.add(
            '[$prevTime] [$prevLevel] $loggerPrefix$prevMessage$repeatSuffix',
          );
        }
      }

      for (final e in entries) {
        final msg = e['message']?.toString() ?? '';
        final lvl = e['level']?.toString() ?? '';
        final log = e['logger']?.toString() ?? '';
        final time = e['timestamp']?.toString() ?? '';

        if (msg == prevMessage && lvl == prevLevel && log == prevLogger) {
          repeatCount++;
        } else {
          flushPrevious();
          prevMessage = msg;
          prevLevel = lvl;
          prevLogger = log;
          prevTime = time;
          repeatCount = 1;
        }
      }
      flushPrevious();

      final lines = compacted.join('\n');
      return CallToolResult(
        content: [
          TextContent(
            text:
                '${entries.length} log entries (${compacted.length} compacted, '
                'buffer total: ${_activeDebugLogs.length}):\n$lines',
          ),
        ],
      );
    }

    _tool(
      'get_debug_logs',
      description:
          'Returns console output the running app printed since FlutterPilot connected — print(), debugPrint(), and dart:developer log() calls. '
          'Supports search query, level filter ("debug", "info", "warning", "error"), since_seconds, and limit.',
      inputSchema: ToolInputSchema(
        properties: {
          'level': JsonSchema.string(
            description:
                'Filter by log level: "debug", "info", "warning", or "error". Omit to return all levels.',
          ),
          'query': JsonSchema.string(
            description: 'Search string to filter log messages.',
          ),
          'since_seconds': JsonSchema.integer(
            description: 'Only return logs captured within the last N seconds.',
          ),
          'limit': JsonSchema.integer(
            description:
                'Maximum number of log entries to return (default: 100).',
          ),
          'logger': JsonSchema.string(
            description:
                'Filter by logger name (partial match). E.g. "debugPrint", "stdout", "print".',
          ),
        },
      ),
      callback: (params, extra) => executeGetLogs(params),
    );

    // Marionette standard alias

    // -- clear_debug_logs -----------------------------------------------------
    Future<CallToolResult> executeClearAllLogs(
      Map<String, dynamic> params,
    ) async {
      final serverCleared = _debugLogBuffer.length;
      _clearDebugLogBuffer();
      final res = await _callExtensionRaw(
        'ext.flutterpilot.clearDebugLogs',
        {},
      );
      if (res.isError) {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Server buffer cleared ($serverCleared entries).'
                  '${res.errorMessage?.contains('zero-code') == true ? '' : ' In-app buffer: ${res.errorMessage}'}',
            ),
          ],
        );
      }
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Log buffers cleared (server: $serverCleared entries, app: cleared).',
          ),
        ],
      );
    }

    _tool(
      'clear_debug_logs',
      description:
          'Clears captured console logs (server and in-app buffers). '
          'Use this before a specific test scenario so you get a clean baseline.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) => executeClearAllLogs(params),
    );

    // -- get_capabilities -----------------------------------------------------
    _tool(
      'get_capabilities',
      description:
          'Returns the server capabilities: connection status, loaded plugins, '
          'available state managers, buffer sizes, and configuration. '
          'CALL THIS FIRST to discover what plugins and tools are available '
          'before attempting state inspection or plugin-specific operations.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        // Probe which plugins are loaded concurrently in parallel
        final pluginProbes = <String, String>{
          'bloc': 'ext.flutterpilot.getBlocStates',
          'riverpod': 'ext.flutterpilot.getRiverpodStates',
          'dio': 'ext.flutterpilot.getNetworkLogs',
          'hive': 'ext.flutterpilot.getHiveContents',
          'shared_preferences': 'ext.flutterpilot.getSharedPreferences',
          'drift': 'ext.flutterpilot.listDriftTables',
        };
        final probeResults = await Future.wait(
          pluginProbes.entries.map((e) async {
            final res = await _callExtensionRaw(e.value, {});
            return MapEntry(e.key, res.isError ? 'not_loaded' : 'loaded');
          }),
        );
        final sdkCapabilities = await _callExtensionRaw(
          'ext.flutterpilot.getCapabilities',
          {},
        );
        final pluginStatus = Map.fromEntries(probeResults);

        final capabilities = {
          'connection': {
            'vmServiceUri': vmServiceUri,
            'connected': _vmService != null,
            'reconnecting': _isReconnecting,
            'activeDevice': _fleetManager.activeDeviceId ?? 'default',
          },
          'config': {
            'allowDestructive': allowDestructive,
            'eventBufferMax': _Constants.eventBufferMax,
            'eventBufferMaxBytes': _Constants.eventBufferMaxBytes,
            'debugLogBufferMax': _Constants.debugLogBufferMax,
            'debugLogBufferMaxBytes': _Constants.debugLogBufferMaxBytes,
            'maxScreenshotBaselines': _Constants.maxScreenshotBaselines,
            'maxScreenshotBaselineBytes': _Constants.maxScreenshotBaselineBytes,
            'maxToolResponseBytes': _Constants.maxToolResponseBytes,
          },
          'plugins': pluginStatus,
          'sdkCapabilities': sdkCapabilities.isError
              ? <String, dynamic>{
                  'status':
                      sdkCapabilities.errorMessage?.contains('zero-code') ==
                          true
                      ? 'flutterpilot_sdk not installed (zero-code mode)'
                      : 'unavailable',
                }
              : sdkCapabilities.data,
          'buffers': {
            'events': _activeEvents.length,
            'debugLogs': _activeDebugLogs.length,
            'screenshotBaselines': _screenshotBaselines.length,
          },
          'fleet': {
            'activeDevice': _fleetManager.activeDeviceId ?? 'default',
            'deviceCount': _fleetManager.listDevices()['total'],
            'parallelOperations': true,
            'routing': 'per-device-context',
          },
        };

        return CallToolResult(
          content: [TextContent(text: jsonEncode(capabilities))],
        );
      },
    );

    _tool(
      'profile_frame_budget',
      description:
          'Microsecond Frame Budget & Jank Pinpointer: Analyzes rolling 120-frame timings (Build, Raster, Total) '
          'and identifies whether UI thread (build/layout) or GPU thread (raster) is causing dropped frames.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getFrameBudgetProfile',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: 'Frame Budget & Jank Profile:\n${jsonEncode(res.data)}',
            ),
          ],
        );
      },
    );

    _tool(
      'get_stream_logs',
      description:
          'Real-Time WebSocket & Stream Channel Inspector: Returns captured incoming and outgoing '
          'real-time messages (WebSockets, Supabase Realtime, EventStreams). '
          'Supports channel filter.',
      inputSchema: ToolInputSchema(
        properties: {
          'channel': JsonSchema.string(
            description: 'Optional channel name to filter messages by.',
          ),
        },
      ),
      callback: (p, e) async {
        final channel = p['channel']?.toString();
        final res = await _callExtensionRaw('ext.flutterpilot.getStreamLogs', {
          'channel': ?channel,
        });
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: 'Real-Time Stream Logs:\n${jsonEncode(res.data)}',
            ),
          ],
        );
      },
    );
  }
}
