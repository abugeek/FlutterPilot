part of '../../flutterpilot_server.dart';

/// Tools for inspecting application state, errors, events, config, and logs.
mixin _AppInspectionToolsMixin on _FlutterPilotServerBase {
  void _registerAppInspectionTools() {
    _registerAppTool(
      name: 'get_app_summary',
      description:
          'Get a 360-degree high-level status of the application. CALL THIS TOOL FIRST upon connecting to find your bearings, identify the current screen, and see if there are any pending errors.',
      extension: 'ext.flutterpilot.getSummary',
      nudge:
          'HINT: Now that you have the summary, use get_widget_tree to find interactable elements or capture_screenshot to see the UI.',
    );

    _registerAppTool(
      name: 'get_errors',
      description:
          'Retrieve the most recent unhandled exceptions and stack traces. CALL THIS whenever you suspect a crash or logic failure.',
      extension: 'ext.flutterpilot.getErrors',
      formatResult: (json) {
        final errors = json['errors'] as List?;
        if (errors == null || errors.isEmpty) return 'No recent errors found.';
        return errors
            .map(
              (e) =>
                  '--- Error ---\n${e['exception']}\n${e['timestamp']}\n${e['stackTrace']}',
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
        if (_eventBuffer.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'No recent events.')],
          );
        }
        return CallToolResult(
          content: [
            TextContent(
              text: _eventBuffer
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
        var entries = _debugLogBuffer.toList();
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
        final lines = entries
            .map(
              (e) {
                final logger = (e['logger'] as String?) ?? '';
                return '[${e['timestamp']}] [${e['level']}] ${logger.isNotEmpty ? '($logger) ' : ''}${e['message']}';
              },
            )
            .join('\n');
        return CallToolResult(
          content: [
            TextContent(
              text:
                  '${entries.length} log entries '
                  '(buffer total: ${_debugLogBuffer.length}):\n$lines',
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
        _debugLogBuffer.clear();
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
        _debugLogBuffer.clear();
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
  }
}
