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
    server.registerTool(
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

    server.registerTool(
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

    server.registerTool(
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
          _fleetManager.registerDevice('default', vmServiceUri);
          return CallToolResult(
            content: [
              TextContent(
                text: ' Connected successfully to Flutter app at $vmServiceUri',
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

    server.registerTool(
      'list_connected_devices',
      description:
          'Lists all registered Flutter devices/instances in the multi-device fleet and which one is active.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        return CallToolResult(
          content: [TextContent(text: _fleetManager.toJsonString())],
        );
      },
    );

    server.registerTool(
      'register_device',
      description:
          'Registers a new device or instance in the multi-device fleet with its name and VM Service URI.',
      inputSchema: ToolInputSchema(
        properties: {
          'id': JsonSchema.string(
            description:
                'A unique identifier or name (e.g. "ios_pro_max", "pixel_8", "web_chrome").',
          ),
          'uri': JsonSchema.string(
            description: 'The VM Service WebSocket URI for that device.',
          ),
        },
        required: ['id', 'uri'],
      ),
      callback: (p, e) async {
        final id = p['id'] as String;
        final uri = p['uri'] as String;
        _fleetManager.registerDevice(id, uri);
        return CallToolResult(
          content: [TextContent(text: 'Registered device "$id" with URI $uri')],
        );
      },
    );

    server.registerTool(
      'switch_device',
      description:
          'Switches the active device to target for all subsequent inspection and UI automation commands.',
      inputSchema: ToolInputSchema(
        properties: {
          'id': JsonSchema.string(
            description:
                'The ID or name of the registered device to switch to.',
          ),
        },
        required: ['id'],
      ),
      callback: (p, e) async {
        final id = p['id'] as String;
        final success = _fleetManager.switchDevice(id);
        if (!success) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'Device "$id" not found in fleet. Call list_connected_devices to see available devices.',
              ),
            ],
          );
        }
        final targetUri = _fleetManager.activeUri;
        final connected = await _connectWithUri(targetUri);
        return CallToolResult(
          isError: !connected,
          content: [
            TextContent(
              text: connected
                  ? 'Switched active device to "$id" ($targetUri) ✅'
                  : 'Switched active device to "$id", but failed to connect to $targetUri ❌',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'get_app_context',
      description:
          'High-speed batch context fetcher: Concurrently gathers 360° app overview, '
          'active errors, and state snapshots (Riverpod/Bloc) in a single ~100ms round-trip. '
          'Saves 2-3 tool call latencies at the start of an agent session or after navigation.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final results = await Future.wait([
          _callExtensionRaw('ext.flutterpilot.getSummary', {}),
          _callExtensionRaw('ext.flutterpilot.getErrors', {}),
          _callExtensionRaw('ext.flutterpilot.getRiverpodStates', {}),
          _callExtensionRaw('ext.flutterpilot.getBlocStates', {}),
        ]);

        final summaryRes = results[0];
        final errorsRes = results[1];
        final riverpodRes = results[2];
        final blocRes = results[3];

        final buffer = StringBuffer();
        buffer.writeln('=== App Summary ===');
        if (!summaryRes.isError && summaryRes.data != null) {
          buffer.writeln(jsonEncode(summaryRes.data));
        } else {
          buffer.writeln('Unavailable or error: ${summaryRes.errorMessage}');
        }

        buffer.writeln('\n=== Active Errors ===');
        if (!errorsRes.isError && errorsRes.data != null) {
          final errors = errorsRes.data!['errors'] as List?;
          if (errors == null || errors.isEmpty) {
            buffer.writeln('No active errors.');
          } else {
            buffer.writeln('${errors.length} error(s) recorded:');
            for (final err in errors.take(3)) {
              buffer.writeln(' • ${(err as Map)['exception']}');
            }
          }
        } else {
          buffer.writeln('No active errors.');
        }

        if (!riverpodRes.isError && riverpodRes.data != null) {
          final states = riverpodRes.data!['states'] as Map?;
          if (states != null && states.isNotEmpty) {
            buffer.writeln('\n=== Riverpod States ===');
            for (final entry in states.entries.take(10)) {
              buffer.writeln(' • ${entry.key}: ${entry.value['value']}');
            }
          }
        }

        if (!blocRes.isError && blocRes.data != null) {
          final states = blocRes.data!['states'] as Map?;
          if (states != null && states.isNotEmpty) {
            buffer.writeln('\n=== Bloc States ===');
            for (final entry in states.entries.take(10)) {
              buffer.writeln(' • ${entry.key}: ${entry.value['state']}');
            }
          }
        }

        final activeLogs = _activeDebugLogs;
        if (activeLogs.isNotEmpty) {
          buffer.writeln('\n=== Recent Debug Logs ===');
          for (final log in activeLogs.reversed.take(5).toList().reversed) {
            buffer.writeln(' [${log['level']}] ${log['message']}');
          }
        }

        return CallToolResult(
          content: [TextContent(text: buffer.toString().trim())],
        );
      },
    );

    _registerAppTool(
      name: 'get_app_summary',
      description:
          'Get a 360-degree overview of the app: current route, widget count, '
          'pending errors, loaded plugins, and FPS stats. '
          'CALL THIS FIRST upon connecting to orient yourself. '
          'AFTER: Use get_widget_tree to find interactable elements, or '
          'capture_screenshot to see the visual state.',
      extension: 'ext.flutterpilot.getSummary',
      nudge:
          'HINT: Now that you have the summary, use get_widget_tree to find interactable elements or capture_screenshot to see the UI.',
    );

    _registerAppTool(
      name: 'get_errors',
      description:
          'Retrieve the most recent unhandled exceptions and stack traces with duplicate aggregation. CALL THIS whenever you suspect a crash or logic failure.',
      extension: 'ext.flutterpilot.getErrors',
      formatResult: (json) {
        final errors = json['errors'] as List?;
        if (errors == null || errors.isEmpty) return 'No recent errors found.';

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
                  '--- Error (x${e['count']}) ---\n${e['exception']}\nLatest: ${e['timestamp']}\n${e['stackTrace'] ?? ''}',
            )
            .join('\n\n');
      },
      nudge:
          'HINT: Analyze the stack trace to find the failing file, then use get_widget_tree to see the state of the UI at failure.',
    );

    server.registerTool(
      'get_recent_events',
      description:
          'Retrieves the last 50 proactive events (errors, taps, state changes) from the stream. Use this to catch up on what happened while you were processing or if the user interacted with the app manually.',
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

    server.registerTool(
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

    server.registerTool(
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

    server.registerTool(
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

    // -- get_debug_logs -------------------------------------------------------
    server.registerTool(
      'get_debug_logs',
      description:
          'Returns captured console output from the running app — including print(), debugPrint(), and dart:developer log() calls. '
          'This replaces the need to manually copy-paste from VS Code debug console. '
          'Use level filter ("debug", "info", "warning", "error") and limit to narrow results. '
          'Call this any time you need to see what the app is printing.',
      inputSchema: ToolInputSchema(
        properties: {
          'level': JsonSchema.string(
            description:
                'Filter by log level: "debug", "info", "warning", or "error". Omit to return all levels.',
          ),
          'limit': JsonSchema.integer(
            description:
                'Maximum number of log entries to return. Defaults to 100. Use smaller values for recent output only.',
          ),
          'logger': JsonSchema.string(
            description:
                'Filter by logger name (partial match). E.g. "debugPrint", "stdout", or a custom logger name.',
          ),
        },
      ),
      callback: (params, extra) async {
        final levelFilter = params['level'] as String?;
        final loggerFilter = params['logger'] as String?;
        final rawLimit = (params['limit'] as int?) ?? 100;
        final limit = rawLimit.clamp(1, _Constants.debugLogBufferMax);
        var entries = _activeDebugLogs;
        if (levelFilter != null && levelFilter.isNotEmpty) {
          entries = entries.where((e) => e['level'] == levelFilter).toList();
        }
        if (loggerFilter != null && loggerFilter.isNotEmpty) {
          entries = entries
              .where(
                (e) =>
                    (e['logger'] as String?)?.contains(loggerFilter) ?? false,
              )
              .toList();
        }
        if (entries.length > limit) {
          entries = entries.sublist(entries.length - limit);
        }
        if (entries.isEmpty) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'No console logs captured yet. '
                    'Ensure FlutterPilot.initialize() is called before runApp().',
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
      },
    );

    // -- clear_debug_logs -----------------------------------------------------
    server.registerTool(
      'clear_debug_logs',
      description:
          'Clears the captured console log buffer on the server side. '
          'Use this before a specific test scenario so you get a clean baseline.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        final count = _debugLogBuffer.length;
        _clearDebugLogBuffer();
        return CallToolResult(
          content: [TextContent(text: 'Cleared $count log entries.')],
        );
      },
    );

    // -- set_log_filter -------------------------------------------------------
    server.registerTool(
      'set_log_filter',
      description:
          'Clears the in-app SDK debug log buffer. Call before a test run '
          'to get a clean log window. '
          'Tip: pair with get_debug_logs(level:"error") after the action.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
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
                    'Server buffer cleared ($serverCleared entries). '
                    'In-app buffer: ${res.errorMessage}',
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
      },
    );

    // -- get_capabilities -----------------------------------------------------
    server.registerTool(
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
              ? <String, dynamic>{'status': 'unavailable'}
              : sdkCapabilities.data,
          'buffers': {
            'events': _activeEvents.length,
            'debugLogs': _activeDebugLogs.length,
            'screenshotBaselines': _screenshotBaselines.length,
          },
        };

        return CallToolResult(
          content: [TextContent(text: jsonEncode(capabilities))],
        );
      },
    );

    server.registerTool(
      'assert_ui_health_batch',
      description:
          'Unified 1-Shot UI Screen Health Auditor: Inspects current screen for RenderFlex overflows, '
          'touch targets smaller than 48x48 dp, and unlabelled interactive controls in <2ms. '
          'Returns a single structured health verdict.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.auditUiHealth',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: 'UI Screen Health Report:\n${jsonEncode(res.data)}',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'hot_restart_and_restore',
      description:
          'Fast Hot Restart & State Re-hydration: Automatically snapshots current app state, '
          'performs hot restart, and re-applies the saved state snapshot. '
          'Keeps the app on the exact same screen and state after restart.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        // 1. Snapshot state
        await _callExtensionRaw('ext.flutterpilot.saveSnapshot', {
          'name': '_auto_hot_restart',
        });

        // 2. Hot restart
        final restartRes = await _callExtensionRaw(
          'ext.flutterpilot.hotRestart',
          {},
        );
        if (restartRes.isError) return restartRes.toCallToolResult();

        // 3. Wait for app rebuild
        await Future.delayed(const Duration(milliseconds: 600));

        // 4. Restore state
        final restoreRes = await _callExtensionRaw(
          'ext.flutterpilot.restoreSnapshot',
          {'name': '_auto_hot_restart'},
        );

        return CallToolResult(
          content: [
            TextContent(
              text:
                  '⚡ Hot restart completed and state snapshot restored: '
                  '${restoreRes.isError ? "State restoration pending" : "State fully restored"}.',
            ),
          ],
        );
      },
    );

    server.registerTool(
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

    server.registerTool(
      'replay_flight_log',
      description:
          'Live Autonomous Flight Replay Engine: Re-executes the recorded rolling 30s user actions, '
          'taps, and gestures live inside the running app in fast-forward mode (~150ms per action). '
          'Enables instant live reproduction of bugs.',
      inputSchema: ToolInputSchema(
        properties: {
          'delayMs': JsonSchema.integer(
            description:
                'Delay between replayed actions in milliseconds (default: 150ms).',
          ),
        },
      ),
      callback: (p, e) async {
        final delayMs = (p['delayMs'] as num?)?.toInt() ?? 150;
        final res = await _callExtensionRaw(
          'ext.flutterpilot.replayFlightLog',
          {'delayMs': delayMs.toString()},
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: '⚡ Live Flight Replay finished: ${jsonEncode(res.data)}',
            ),
          ],
        );
      },
    );

    server.registerTool(
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
