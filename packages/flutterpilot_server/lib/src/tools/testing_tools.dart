part of '../../flutterpilot_server.dart';

/// Tools for recording interactions, generating tests, invoking custom tools,
/// and making assertions about widget state.
mixin _TestingToolsMixin on _FlutterPilotServerBase {
  void _registerTestingTools() {
    server.registerTool(
      'start_recording',
      description:
          'Starts recording manual interactions. User should perform the flow in the app while this is active.',
      inputSchema: ToolInputSchema(
        properties: {'deviceId': _deviceIdProperty()},
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.startRecording',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'stop_and_generate_test',
      description:
          'Stops recording and returns a log of actions. Use your LLM capability to convert this log into a Flutter `testWidgets` block.',
      inputSchema: ToolInputSchema(
        properties: {'deviceId': _deviceIdProperty()},
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.stopRecording',
          _withDeviceId(p),
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Recorded Actions (Convert to Test):\n${jsonEncode(res.data?['actions'])}\n\nHINT: Create a new file in the test/ directory and paste this as a testWidgets block.',
            ),
          ],
          isError: false,
        );
      },
    );

    _registerAppTool(
      name: 'list_custom_tools',
      description:
          'Discover additional app-specific tools registered by the developer.',
      extension: 'ext.flutterpilot.listCustomTools',
    );

    server.registerTool(
      'call_custom_tool',
      description:
          'Executes an app-specific tool defined by the developer. CALL THIS if you see a relevant tool listed in `list_custom_tools`.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(
            description:
                'The custom tool name as registered via FlutterPilot.registerCustomTool().',
          ),
          'params': JsonSchema.object(),
        },
        required: ['name'],
      ),
      callback: (p, e) async {
        if (!allowDestructive) return _destructiveOperationDenied();
        final res = await _callExtensionRaw(
          'ext.flutterpilot.callCustomTool',
          p,
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'assert_widget_visible',
      description:
          'Asserts that a widget with the given Key is present and has layout. Returns error if the assertion fails — treat this as a test failure.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The ValueKey string of the widget to assert is visible.',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.assertWidgetVisible',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'assert_text_visible',
      description:
          'Asserts that the given text is visible on screen. Set exact=true for exact match, false (default) for substring match.',
      inputSchema: ToolInputSchema(
        properties: {
          'text': JsonSchema.string(
            description: 'The text string to assert is visible on screen.',
          ),
          'exact': JsonSchema.boolean(
            description:
                'If true, requires an exact text match. If false (default), a substring match is used.',
          ),
        },
        required: ['text'],
      ),
      callback: (p, e) async {
        final args = {
          'text': p['text'] as String,
          if (p['exact'] != null) 'exact': p['exact'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.assertTextVisible',
          _withDeviceId(p, args),
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'assert_widget_count',
      description:
          'Asserts the exact number of widgets of a given type (e.g. "ListTile", "ElevatedButton") on screen. Returns error if count does not match.',
      inputSchema: ToolInputSchema(
        properties: {
          'type': JsonSchema.string(
            description:
                'Widget type name to count (e.g. "ElevatedButton", "Text", "ListTile").',
          ),
          'count': JsonSchema.integer(
            description: 'Expected number of widgets of the given type.',
          ),
        },
        required: ['type', 'count'],
      ),
      callback: (p, e) async {
        final args = {
          'type': p['type'] as String,
          'count': p['count'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.assertWidgetCount',
          _withDeviceId(p, args),
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'assert_widget_enabled',
      description:
          'Asserts that the widget identified by key is ENABLED '
          '(has a non-null onPressed / onTap / onChanged callback). '
          'Returns error if the widget is disabled or not found.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The ValueKey string of the widget to assert is enabled.',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.assertWidgetEnabled',
          _withDeviceId(p, {'key': p['key'].toString()}),
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'assert_widget_disabled',
      description:
          'Asserts that the widget identified by key is DISABLED '
          '(onPressed / onTap / onChanged is null). '
          'Returns error if the widget is enabled or not found.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The ValueKey string of the widget to assert is disabled.',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.assertWidgetDisabled',
          _withDeviceId(p, {'key': p['key'].toString()}),
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'get_perf_metrics',
      description:
          'Get current FPS and Heap Memory usage. CALL THIS to verify that code optimizations actually improved performance.',
      inputSchema: ToolInputSchema(
        properties: {'deviceId': _deviceIdProperty()},
      ),
      callback: (p, e) async {
        final fpsRes = await _callExtensionRaw(
          'ext.flutterpilot.getPerfMetrics',
          _withDeviceId(p),
        );
        String memory = 'N/A';
        final vmService = await _vmServiceForParameters(p);
        if (vmService != null) {
          final vm = await vmService.getVM();
          final mainIsolateId = vm.isolates?.firstOrNull?.id;
          if (mainIsolateId != null) {
            final usage = await vmService.getMemoryUsage(mainIsolateId);
            memory =
                '${((usage.heapUsage ?? 0) / (1024 * 1024)).toStringAsFixed(2)} MB';
          }
        }
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'FPS: ${fpsRes.data?['fps'] ?? 'N/A'}\nHeap: $memory\n\nHINT: If FPS is below 60, use show_performance_overlay to find heavy build cycles.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'run_chaos_fuzzing',
      description:
          'Runs autonomous monkey/chaos stress fuzzing against the running Flutter app for a specified duration. '
          'Randomly clicks interactive elements, inputs text, and navigates to detect crashes and unhandled exceptions.',
      inputSchema: ToolInputSchema(
        properties: {
          'durationSeconds': JsonSchema.integer(
            description:
                'Duration to run chaos fuzzing in seconds (default: 5).',
          ),
          'eventRatePerSecond': JsonSchema.integer(
            description: 'Rate of chaos events per second (default: 5).',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.runChaosFuzzing',
          _withDeviceId(p, {
            if (p['durationSeconds'] != null)
              'durationSeconds': p['durationSeconds'].toString(),
            if (p['eventRatePerSecond'] != null)
              'eventRatePerSecond': p['eventRatePerSecond'].toString(),
          }),
        );
        if (res.isError) return res.toCallToolResult();
        final events = res.data?['eventsExecuted'] ?? 0;
        final errors = res.data?['newErrorsCaught'] ?? 0;
        final duration = res.data?['durationMs'] ?? 0;
        return CallToolResult(
          content: [
            TextContent(
              text:
                  '🐒 **Chaos Fuzzing Finished (${(duration / 1000).toStringAsFixed(1)}s):**\n'
                  '- Events Executed: $events\n'
                  '- Unhandled Crashes Caught: $errors\n'
                  '- Result: ${errors == 0 ? "🟢 APP STABLE (0 Crashes)" : "🚨 UNHANDLED EXCEPTIONS DETECTED - Call get_flight_log"}',
            ),
          ],
        );
      },
    );
  }
}
