part of '../../flutterpilot_server.dart';

/// Tools for self-heal status, crash reports, diagnostics, hot reload/restart.
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
      'diagnose_last_error',
      description:
          '[DEPRECATED] Use `get_latest_crash_report` instead for better structured data.',
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
