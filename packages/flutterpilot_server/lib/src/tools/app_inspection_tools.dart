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
      'connect_app',
      description:
          'Connects to a running Flutter app: the VM service URI flutter run '
          'prints, or without uri the one found in the project or the '
          "client's workspace folders. Needed only when the app was not found "
          'automatically or was restarted.',
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
                text: uri == null
                    ? 'No running Flutter app found. '
                          '${VmDiscoveryService.howToStart}'
                    : 'No Flutter app answers at '
                          '${FleetManager.shortUri(uri)} (or it is not a local '
                          'address). Is it still running in debug mode?',
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

    String formatErrors(Map<String, dynamic> json) {
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
    }

    _tool(
      'get_errors',
      description:
          'Recent uncaught exceptions, deduplicated, with your source frame '
          '(file:line) and, for layout errors, the culprit widget. '
          'report:true returns the structured report of the latest crash '
          'instead: exception, stack, route, recent actions and state.',
      inputSchema: ToolInputSchema(
        properties: {
          'report': JsonSchema.boolean(
            description: 'Return the latest crash report instead of the list.',
          ),
        },
      ),
      callback: (p, e) async {
        if (p['report'] == true) {
          final report = await _selfHealManager.getLatestReport((ext) async {
            final res = await _callExtensionRaw(ext, {});
            return res.isError ? 'N/A' : res.data;
          });
          return CallToolResult(
            content: [
              TextContent(
                text: report?.toMarkdown() ?? 'No crash reports available.',
              ),
            ],
          );
        }
        final res = await _callExtensionRaw('ext.flutterpilot.getErrors', p);
        if (res.isError) return res.toCallToolResult();
        final text = formatErrors(res.data!);
        return CallToolResult(
          content: [
            TextContent(
              text: FlutterPilotServer._boundToolText(
                _selfHealManager.isUnstable
                    ? 'An uncaught exception happened since the last hot '
                          'reload (get_errors(report: true): its stack and the '
                          'app state).\n\n$text'
                    : text,
              ),
            ),
          ],
        );
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

    // -- get_debug_logs(clear: true) ---------------------------------------
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
      'get_debug_logs',
      description:
          'Returns console output the running app printed since FlutterPilot connected — print(), debugPrint(), and dart:developer log() calls. '
          'Supports search query, level filter ("debug", "info", "warning", "error"), since_seconds, and limit. '
          'clear:true empties the server and in-app buffers instead (a clean baseline before a test).',
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
          'clear': JsonSchema.boolean(
            description: 'Clear the captured logs instead of reading them.',
          ),
        },
      ),
      callback: (params, extra) => params['clear'] == true
          ? executeClearAllLogs(params)
          : executeGetLogs(params),
    );

    // -- get_capabilities -----------------------------------------------------
    _tool(
      'get_capabilities',
      description:
          'Server and app setup: connection, which FlutterPilot plugins the '
          'app registered, SDK capabilities, Dart VM version, pid and '
          'isolates, buffer limits. Use when a tool is missing or refused.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        const pluginExtensions = {
          'riverpod': 'getRiverpodStates',
          'bloc': 'getBlocStates',
          'dio': 'getNetworkLogs',
          'hive': 'getHiveContents',
          'drift': 'listDriftTables',
          'sqflite': 'listSqfliteDatabases',
          'shared_preferences': 'getSharedPreferences',
          'supabase': 'getSupabaseAuth',
          'go_router': 'getGoRouterState',
          'connectivity': 'getConnectivity',
          'firebase': 'getFirebaseAuth',
          'secure_storage': 'getSecureStorageKeys',
        };
        final vmService = await _vmServiceForParameters(params);
        final rpcs = <String>{};
        Map<String, dynamic>? vmInfo;
        if (vmService != null) {
          try {
            final vm = await vmService.getVM();
            final isolates = <String>[];
            for (final ref in vm.isolates ?? const <IsolateRef>[]) {
              isolates.add(ref.name ?? ref.id ?? '?');
              rpcs.addAll(
                (await vmService.getIsolate(ref.id!)).extensionRPCs ?? const [],
              );
            }
            vmInfo = {
              'version': vm.version,
              'pid': vm.pid,
              'os': vm.operatingSystem,
              'isolates': isolates,
            };
          } catch (e) {
            vmInfo = {'error': '$e'};
          }
        }
        final pluginStatus = {
          for (final MapEntry(key: plugin, value: ext)
              in pluginExtensions.entries)
            plugin: rpcs.contains('ext.flutterpilot.$ext')
                ? 'loaded'
                : 'not_loaded',
        };
        final sdkCapabilities = await _callExtensionRaw(
          'ext.flutterpilot.getCapabilities',
          {},
        );

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
          'vm': ?vmInfo,
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
          'Frame timings of the last 120 frames: p50/p90/p99 build, raster and '
          'total, jank count, and whether the UI thread (build/layout) or the '
          'raster thread causes dropped frames. profile_action explains '
          'the slow frames of one interaction (phases, rebuilt widgets).',
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
              text:
                  'Frame Budget & Jank Profile:\n${jsonEncode(res.data)}\n'
                  '${_activeContext?.buildMode == BuildMode.profile ? profileBuildNote : debugBuildNote}',
            ),
          ],
        );
      },
    );
  }
}
