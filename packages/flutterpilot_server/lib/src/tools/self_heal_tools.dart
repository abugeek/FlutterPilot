part of '../../flutterpilot_server.dart';

/// Tools for self-heal status, crash flight recorder, reproduction tests, diagnostics, and hot reload/restart.
mixin _SelfHealToolsMixin on _FlutterPilotServerBase {
  void _registerSelfHealTools() {
    server.registerTool(
      'get_self_heal_status',
      description:
          'Check if the application is currently in an unstable/crash state. Use this to verify if your last fix worked or if a new crash was intercepted.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final status = _selfHealManager.isUnstable ? '🚨 UNSTABLE' : '✅ STABLE';
        return CallToolResult(
          content: [TextContent(text: 'Current App Status: $status')],
        );
      },
    );

    server.registerTool(
      'get_latest_crash_report',
      description:
          'Retrieve the most recent structured crash report. CALL THIS immediately if you receive a Self-Heal notification or if `get_self_heal_status` returns UNSTABLE.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final report = _selfHealManager.lastCrashReport;
        if (report == null) {
          return CallToolResult(
            content: [TextContent(text: 'No crash reports available.')],
          );
        }
        return CallToolResult(
          content: [TextContent(text: report.toMarkdown())],
        );
      },
    );

    server.registerTool(
      'get_flight_log',
      description:
          'Retrieves the chronological 30-60 second rolling flight recorder timeline (user taps, route changes, state mutations, and network requests) leading up to the current state or crash.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.getFlightLog', {});
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: '### 🛫 Continuous Flight Recorder Log\n```json\n${json.encode(res.data)}\n```',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'generate_repro_test',
      description:
          'Synthesizes a standalone, executable Flutter widget test (`test/repro_test.dart`) from the continuous Flight Recorder session leading up to a crash or bug. '
          'Run the generated test with `flutter test test/repro_test.dart` to verify reproduction and fix.',
      inputSchema: ToolInputSchema(
        properties: {
          'testName': JsonSchema.string(
            description: 'Optional descriptive name for the test.',
          ),
          'widgetName': JsonSchema.string(
            description: 'Root widget or screen name to mount (default: "MyApp()").',
          ),
          'writeToDisk': JsonSchema.boolean(
            description: 'Whether to automatically write the test to test/repro_test.dart (default: false).',
          ),
          'filePath': JsonSchema.string(
            description: 'Custom file path to write to (default: "test/repro_test.dart").',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.generateReproTest', {
          if (p['testName'] != null) 'testName': p['testName'].toString(),
          if (p['widgetName'] != null) 'widgetName': p['widgetName'].toString(),
        });
        if (res.isError) return res.toCallToolResult();

        final code = res.data?['code']?.toString() ?? '';
        final writeToDisk = p['writeToDisk'] == true;
        final targetPath = (p['filePath']?.toString() ?? 'test/repro_test.dart');

        String diskStatus = '';
        if (writeToDisk && code.isNotEmpty) {
          try {
            final file = File(targetPath);
            if (!file.parent.existsSync()) {
              file.parent.createSync(recursive: true);
            }
            file.writeAsStringSync(code);
            diskStatus = '\n\n✅ Wrote reproduction test to `$targetPath`. Run with:\n`flutter test $targetPath`';
          } catch (err) {
            diskStatus = '\n\n⚠️ Failed to write to disk: $err';
          }
        }

        return CallToolResult(
          content: [
            TextContent(
              text: '### 🧪 Auto-Generated Reproduction Test$diskStatus\n\n```dart\n$code\n```',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'export_test_suite',
      description:
          'Exports recorded user journeys and flight sessions as production-ready test suites for Patrol, standard Flutter Integration Tests, or Widget Tests. '
          'Can write the file directly to disk (e.g. integration_test/flow_test.dart or test/flow_test.dart).',
      inputSchema: ToolInputSchema(
        properties: {
          'framework': JsonSchema.string(
            description: 'Target test framework: "patrol", "integration_test", or "widget_test" (default: "patrol").',
            enumValues: ['patrol', 'integration_test', 'widget_test'],
          ),
          'testName': JsonSchema.string(
            description: 'Descriptive test name.',
          ),
          'appWidget': JsonSchema.string(
            description: 'Target app/screen widget name (e.g. "MyApp()", "CheckoutScreen()").',
          ),
          'writeToDisk': JsonSchema.boolean(
            description: 'Whether to write generated test to disk (default: false).',
          ),
          'filePath': JsonSchema.string(
            description: 'File path to write (e.g. "integration_test/checkout_flow_test.dart").',
          ),
        },
      ),
      callback: (p, e) async {
        final framework = p['framework']?.toString() ?? 'patrol';
        final res = await _callExtensionRaw('ext.flutterpilot.exportTestSuite', {
          'framework': framework,
          if (p['testName'] != null) 'testName': p['testName'].toString(),
          if (p['appWidget'] != null) 'appWidget': p['appWidget'].toString(),
        });
        if (res.isError) return res.toCallToolResult();

        final code = res.data?['code']?.toString() ?? '';
        final writeToDisk = p['writeToDisk'] == true;
        final defaultPath = framework == 'widget_test'
            ? 'test/flow_test.dart'
            : 'integration_test/flow_test.dart';
        final targetPath = p['filePath']?.toString() ?? defaultPath;

        String diskStatus = '';
        if (writeToDisk && code.isNotEmpty) {
          try {
            final file = File(targetPath);
            if (!file.parent.existsSync()) {
              file.parent.createSync(recursive: true);
            }
            file.writeAsStringSync(code);
            diskStatus = '\n\n✅ Wrote test suite to `$targetPath`.';
          } catch (err) {
            diskStatus = '\n\n⚠️ Failed to write to disk: $err';
          }
        }

        return CallToolResult(
          content: [
            TextContent(
              text: '### 🧪 Auto-Generated Test Suite ($framework)$diskStatus\n\n```dart\n$code\n```',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'clear_flight_log',
      description: 'Clears the flight recorder event buffer.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.clearFlightLog', {});
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'diagnose_last_error',
      description:
          '[DEPRECATED] Use `get_latest_crash_report` or `get_flight_log` instead.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final report = _selfHealManager.lastCrashReport;
        if (report == null) {
          return CallToolResult(
            content: [TextContent(text: 'No crash reports available.')],
          );
        }
        return CallToolResult(
          content: [TextContent(text: report.toMarkdown())],
        );
      },
    );

    server.registerTool(
      'hot_reload',
      description:
          'Trigger a source code hot reload. CALL THIS after you have modified a .dart file to apply the fix to the running app.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'Not connected')],
            isError: true,
          );
        }
        final vm = await _vmService!.getVM();
        final mainIsolateId = vm.isolates?.firstOrNull?.id;
        if (mainIsolateId == null) {
          return CallToolResult(
            content: [TextContent(text: 'No main isolate found')],
            isError: true,
          );
        }
        try {
          await _vmService!.reloadSources(mainIsolateId);
          await _vmService!.callServiceExtension(
            'ext.flutter.reassemble',
            isolateId: mainIsolateId,
          );
          _selfHealManager.reset();
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Hot Reload successful! HINT: Now call get_self_heal_status to verify the fix.',
              ),
            ],
          );
        } catch (err) {
          return CallToolResult(
            content: [TextContent(text: 'Hot Reload failed: $err')],
            isError: true,
          );
        }
      },
    );

    server.registerTool(
      'hot_restart',
      description:
          'Trigger a full app hot restart. CALL THIS for structural code changes (main(), providers) or to reset app state.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'Not connected')],
            isError: true,
          );
        }
        final vm = await _vmService!.getVM();
        final mainIsolateId = vm.isolates?.firstOrNull?.id;
        if (mainIsolateId == null) {
          return CallToolResult(
            content: [TextContent(text: 'No main isolate found')],
            isError: true,
          );
        }
        try {
          await _vmService!.callServiceExtension(
            'ext.flutter.hotRestart',
            isolateId: mainIsolateId,
          );
          _selfHealManager.reset();
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Hot Restart triggered! HINT: App state is reset. Use get_app_summary to re-orient.',
              ),
            ],
          );
        } catch (err) {
          return CallToolResult(
            content: [TextContent(text: 'Hot Restart failed: $err')],
            isError: true,
          );
        }
      },
    );
  }
}
