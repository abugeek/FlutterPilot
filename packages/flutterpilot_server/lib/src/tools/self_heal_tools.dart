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
      inputSchema: ToolInputSchema(
        properties: {'deviceId': _deviceIdProperty()},
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getFlightLog',
          _withDeviceId(p),
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  '### 🛫 Continuous Flight Recorder Log\n```json\n${json.encode(res.data)}\n```',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'generate_repro_test',
      description:
          'Synthesizes a standalone, executable Flutter widget test (`test/repro_test.dart`) from the continuous Flight Recorder session leading up to a crash or bug. '
          'Run the generated test with `flutter test test/repro_test.dart` to verify reproduction and fix. '
          'CRASH-REPRODUCTION ONLY — do not use this to verify a routine tap/form/navigation change on the '
          'already-running app; spinning up a cold `flutter test` process is far slower than the delta already '
          'returned by tap_widget/enter_text/execute_action_chain, or a direct assert_widget_visible / '
          'assert_text_visible / assert_widget_count check against the live app.',
      inputSchema: ToolInputSchema(
        properties: {
          'testName': JsonSchema.string(
            description: 'Optional descriptive name for the test.',
          ),
          'widgetName': JsonSchema.string(
            description:
                'Root widget or screen name to mount (default: "MyApp()").',
          ),
          'writeToDisk': JsonSchema.boolean(
            description:
                'Whether to automatically write the test to test/repro_test.dart (default: false).',
          ),
          'filePath': JsonSchema.string(
            description:
                'Custom file path to write to (default: "test/repro_test.dart").',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.generateReproTest',
          _withDeviceId(p, {
            if (p['testName'] != null) 'testName': p['testName'].toString(),
            if (p['widgetName'] != null)
              'widgetName': p['widgetName'].toString(),
          }),
        );
        if (res.isError) return res.toCallToolResult();

        final code = res.data?['code']?.toString() ?? '';
        final writeToDisk = p['writeToDisk'] == true;
        final targetPath =
            (p['filePath']?.toString() ?? 'test/repro_test.dart');

        if (writeToDisk && !allowDestructive) {
          return _destructiveOperationDenied();
        }

        String diskStatus = '';
        if (writeToDisk && code.isNotEmpty) {
          try {
            final file = path.isAbsolute(targetPath)
                ? File(targetPath)
                : File(path.join(_projectRoot.path, targetPath));
            if (!file.parent.existsSync()) {
              file.parent.createSync(recursive: true);
            }
            file.writeAsStringSync(code);
            diskStatus =
                '\n\n✅ Wrote reproduction test to `${file.path}`. Run with:\n`flutter test ${path.relative(file.path, from: _projectRoot.path)}`';
          } catch (err) {
            diskStatus = '\n\n⚠️ Failed to write to disk: $err';
          }
        }

        return CallToolResult(
          content: [
            TextContent(
              text:
                  '### 🧪 Auto-Generated Reproduction Test$diskStatus\n\n```dart\n$code\n```',
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
            description:
                'Target test framework: "patrol", "integration_test", or "widget_test" (default: "patrol").',
            enumValues: ['patrol', 'integration_test', 'widget_test'],
          ),
          'testName': JsonSchema.string(description: 'Descriptive test name.'),
          'appWidget': JsonSchema.string(
            description:
                'Target app/screen widget name (e.g. "MyApp()", "CheckoutScreen()").',
          ),
          'writeToDisk': JsonSchema.boolean(
            description:
                'Whether to write generated test to disk (default: false).',
          ),
          'filePath': JsonSchema.string(
            description:
                'File path to write (e.g. "integration_test/checkout_flow_test.dart").',
          ),
        },
      ),
      callback: (p, e) async {
        final framework = p['framework']?.toString() ?? 'patrol';
        final res = await _callExtensionRaw(
          'ext.flutterpilot.exportTestSuite',
          _withDeviceId(p, {
            'framework': framework,
            if (p['testName'] != null) 'testName': p['testName'].toString(),
            if (p['appWidget'] != null) 'appWidget': p['appWidget'].toString(),
          }),
        );
        if (res.isError) return res.toCallToolResult();

        final code = res.data?['code']?.toString() ?? '';
        final writeToDisk = p['writeToDisk'] == true;
        final defaultPath = framework == 'widget_test'
            ? 'test/flow_test.dart'
            : 'integration_test/flow_test.dart';
        final targetPath = p['filePath']?.toString() ?? defaultPath;

        if (writeToDisk && !allowDestructive) {
          return _destructiveOperationDenied();
        }

        String diskStatus = '';
        if (writeToDisk && code.isNotEmpty) {
          try {
            final file = path.isAbsolute(targetPath)
                ? File(targetPath)
                : File(path.join(_projectRoot.path, targetPath));
            if (!file.parent.existsSync()) {
              file.parent.createSync(recursive: true);
            }
            file.writeAsStringSync(code);
            diskStatus = '\n\n✅ Wrote test suite to `${file.path}`.';
          } catch (err) {
            diskStatus = '\n\n⚠️ Failed to write to disk: $err';
          }
        }

        return CallToolResult(
          content: [
            TextContent(
              text:
                  '### 🧪 Auto-Generated Test Suite ($framework)$diskStatus\n\n```dart\n$code\n```',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'clear_flight_log',
      description: 'Clears the flight recorder event buffer.',
      inputSchema: ToolInputSchema(
        properties: {'deviceId': _deviceIdProperty()},
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.clearFlightLog',
          _withDeviceId(p),
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'diagnose_last_error',
      description:
          'Alias for `get_latest_crash_report`. Returns structured crash diagnostics and state inspection.',
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
          'Recompile edited .dart files and hot reload them into the running app, keeping state. '
          'CALL THIS after modifying Dart source. Requires the app to be started with `flutter run` or an IDE debug session.',
      inputSchema: ToolInputSchema(
        properties: {'deviceId': _deviceIdProperty()},
      ),
      callback: (p, e) => _callFlutterToolsService(
        p,
        'reloadSources',
        'Hot reload applied. HINT: call get_self_heal_status to verify the fix.',
      ),
    );

    server.registerTool(
      'hot_restart',
      description:
          'Recompile and hot restart the app (state is reset). CALL THIS for changes hot reload cannot apply: main(), '
          'initState, global/static initializers, enums, generic type changes.',
      inputSchema: ToolInputSchema(
        properties: {'deviceId': _deviceIdProperty()},
      ),
      callback: (p, e) => _callFlutterToolsService(
        p,
        'hotRestart',
        'Hot restart complete. App state is reset; use get_app_summary to re-orient.',
      ),
    );

    server.registerTool(
      'generate_pr_report',
      description:
          'Auto-generates a ready-to-paste GitHub Pull Request Markdown report summarizing the verified changes, '
          'UI Health Audit (0 overflows), test results, and visual proof replay links.',
      inputSchema: ToolInputSchema(
        properties: {
          'title': JsonSchema.string(
            description:
                'Pull Request title (e.g. "feat: implement responsive product checkout").',
          ),
          'description': JsonSchema.string(
            description: 'Summary of what was built, changed, or fixed.',
          ),
          'generatedTestPath': JsonSchema.string(
            description:
                'Path to synthesized test file if generated (e.g. "integration_test/flow_test.dart").',
          ),
          'gifPath': JsonSchema.string(
            description:
                'Path to exported session GIF if created (e.g. "artifacts/demo.gif").',
          ),
        },
        required: ['title'],
      ),
      callback: (p, e) async {
        final title = p['title'].toString();
        final desc = p['description']?.toString();
        final testPath = p['generatedTestPath']?.toString();
        final gifPath = p['gifPath']?.toString();

        // Run fresh screen health audit
        final auditRes = await _callExtensionRaw(
          'ext.flutterpilot.auditScreenHealth',
          _withDeviceId(p),
        );
        final auditData = auditRes.data;

        final buffer = StringBuffer();
        buffer.writeln('# 🚀 $title\n');
        if (desc != null && desc.isNotEmpty) {
          buffer.writeln('## 📝 Description\n$desc\n');
        }

        final isHealthy = auditData?['isHealthy'] == true;
        final overflowCount = auditData?['overflowCount'] ?? 0;
        final a11yCount = auditData?['accessibilityIssueCount'] ?? 0;

        buffer.writeln('## 🏥 Autonomous Quality & Screen Health Audit');
        buffer.writeln('| Check | Status | Details |');
        buffer.writeln('|---|---|---|');
        buffer.writeln(
          '| **Layout Overflows** | ${overflowCount == 0 ? "✅ Passed" : "❌ Failed"} | $overflowCount RenderFlex errors |',
        );
        buffer.writeln(
          '| **Touch Target Accessibility** | ${a11yCount == 0 ? "✅ Passed" : "⚠️ Warnings"} | $a11yCount touch targets <48x48 dp |',
        );
        buffer.writeln(
          '| **Overall Health** | ${isHealthy ? "🟢 Clean & Production Ready" : "🟡 Needs Review"} | Verified via FlutterPilot |',
        );
        buffer.writeln();

        if (gifPath != null && gifPath.isNotEmpty) {
          buffer.writeln(
            '## 🎬 Visual Proof & Session Replay\n![$title]($gifPath)\n',
          );
        }
        if (testPath != null && testPath.isNotEmpty) {
          buffer.writeln(
            '## 🧪 Synthesized Automated Test\nGenerated test suite available at: `$testPath`\n',
          );
        }
        buffer.writeln('---');
        buffer.writeln(
          '*Automated verification generated with [FlutterPilot](https://github.com/abugeek/FlutterPilot) 🚀*',
        );

        return CallToolResult(content: [TextContent(text: buffer.toString())]);
      },
    );
  }

  /// Calls a service that flutter_tools registers on the VM service
  /// (`reloadSources`, `hotRestart`). Only flutter_tools can recompile the
  /// edited sources; the VM's own reloadSources would reload the old kernel.
  Future<CallToolResult> _callFlutterToolsService(
    Map<String, dynamic> p,
    String service,
    String successText,
  ) async {
    final context = await _deviceContextForParameters(p);
    final vmService = context?.service;
    if (context == null || vmService == null) {
      return CallToolResult(
        content: [TextContent(text: 'Not connected')],
        isError: true,
      );
    }
    // Registrations are replayed asynchronously right after connecting.
    for (
      var i = 0;
      i < 20 && !context.registeredServices.containsKey(service);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final method = context.registeredServices[service];
    if (method == null) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'No "$service" service on this VM service. Hot reload/restart only work when the app was launched '
                'by `flutter run` (or an IDE debug session) and FlutterPilot is connected to the URI it printed. '
                'Otherwise ask the user to press r / R in their flutter run terminal.',
          ),
        ],
        isError: true,
      );
    }
    try {
      final isolateId = (await vmService.getVM()).isolates?.firstOrNull?.id;
      await vmService
          .callMethod(method, isolateId: isolateId)
          .timeout(const Duration(minutes: 2));
      _selfHealManager.reset();
      return CallToolResult(content: [TextContent(text: successText)]);
    } catch (err) {
      final details = err is RPCError
          ? '${err.message} ${err.details ?? ''}'
          : '$err';
      return CallToolResult(
        content: [
          TextContent(
            text:
                '$service failed: $details\nHINT: usually a compile error — run `dart analyze` on the edited files, '
                'fix, and retry. Some changes (main(), static initializers) need hot_restart.',
          ),
        ],
        isError: true,
      );
    }
  }
}
