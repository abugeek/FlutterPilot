part of '../../flutterpilot_server.dart';

/// Tools for self-heal status, crash flight recorder, reproduction tests, diagnostics, and hot reload/restart.
mixin _SelfHealToolsMixin on _FlutterPilotServerBase {
  void _registerSelfHealTools() {
    _tool(
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

    _tool(
      'get_latest_crash_report',
      description:
          'Retrieve the most recent structured crash report. CALL THIS immediately if you receive a Self-Heal notification or if `get_self_heal_status` returns UNSTABLE.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final report = await _selfHealManager.getLatestReport((ext) async {
          final res = await _callExtensionRaw(ext, {});
          return res.isError ? 'N/A' : res.data;
        });
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

    _tool(
      'get_flight_log',
      description:
          'Retrieves the chronological 30-60 second rolling flight recorder timeline (user taps, route changes, state mutations, and network requests) leading up to the current state or crash.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getFlightLog',
          {},
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

    _tool(
      'clear_flight_log',
      description: 'Clears the flight recorder event buffer.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.clearFlightLog',
          {},
        );
        return res.toCallToolResult();
      },
    );

    _tool(
      'diagnose_last_error',
      description:
          'Alias for `get_latest_crash_report`. Returns structured crash diagnostics and state inspection.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final report = await _selfHealManager.getLatestReport((ext) async {
          final res = await _callExtensionRaw(ext, {});
          return res.isError ? 'N/A' : res.data;
        });
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

    _tool(
      'hot_reload',
      description:
          'Recompile edited .dart files and hot reload them into the running app, keeping state. '
          'CALL THIS after modifying Dart source. Requires the app to be started with `flutter run` or an IDE debug session.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) => _callFlutterToolsService(
        p,
        'reloadSources',
        'Hot reload applied. HINT: call get_errors to confirm the error is gone.',
      ),
    );

    _tool(
      'hot_restart',
      description:
          'Recompile and hot restart the app (state is reset). CALL THIS for changes hot reload cannot apply: main(), '
          'initState, global/static initializers, enums, generic type changes.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) => _callFlutterToolsService(
        p,
        'hotRestart',
        'Hot restart complete. App state is reset; use get_app_summary to re-orient.',
      ),
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
