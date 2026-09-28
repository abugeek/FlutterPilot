part of '../../flutterpilot_server.dart';

/// Tools for self-heal status, crash flight recorder, reproduction tests, diagnostics, and hot reload/restart.
mixin _SelfHealToolsMixin on _FlutterPilotServerBase {
  void _registerSelfHealTools() {
    _tool(
      'get_flight_log',
      description:
          'Timeline of the last 30-60 s: taps, route changes, state changes '
          'and network requests, oldest first. Use to see what led up to an '
          'error. clear:true empties it instead.',
      inputSchema: ToolInputSchema(
        properties: {
          'clear': JsonSchema.boolean(
            description: 'Clear the timeline instead of reading it.',
          ),
        },
      ),
      callback: (p, e) async {
        if (p['clear'] == true) {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.clearFlightLog',
            {},
          );
          return res.isError
              ? res.toCallToolResult()
              : CallToolResult(
                  content: [TextContent(text: 'Flight log cleared.')],
                );
        }
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getFlightLog',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [TextContent(text: 'Flight log: ${json.encode(res.data)}')],
        );
      },
    );

    _tool(
      'hot_reload',
      description:
          'Recompiles edited .dart files and hot reloads them into the running '
          'app, keeping state. restart:true does a hot restart instead (state '
          'is reset) — needed for main(), initState, global/static '
          'initializers, enums, generic type changes and provider '
          'definitions. Needs an app started by `flutter run` or an IDE '
          'debug session.',
      inputSchema: ToolInputSchema(
        properties: {
          'restart': JsonSchema.boolean(
            description: 'Hot restart instead of hot reload.',
          ),
        },
      ),
      callback: (p, e) => p['restart'] == true
          ? _callFlutterToolsService(
              p,
              'hotRestart',
              'Hot restart complete. App state is reset; use get_app_summary to re-orient.',
            )
          : _callFlutterToolsService(
              p,
              'reloadSources',
              'Hot reload applied. HINT: call get_errors to confirm the error is gone.',
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
      final hadSdk =
          service == 'hotRestart' && await _hasSdkExtensions(vmService);
      await vmService
          .callMethod(method, isolateId: isolateId)
          .timeout(const Duration(minutes: 2));
      _selfHealManager.reset();
      if (service == 'hotRestart' &&
          !await _waitForRestartedApp(vmService, sdk: hadSdk)) {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  '$successText\nBut the restarted app had not drawn its first '
                  'frame${hadSdk ? ' or registered FlutterPilot' : ''} after '
                  '10 s: main() may be stuck (awaiting something before '
                  'runApp). Check get_logs.',
            ),
          ],
        );
      }
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
                'fix, and retry. Some changes (main(), static initializers) need hot_reload(restart: true).',
          ),
        ],
        isError: true,
      );
    }
  }

  static Future<bool> _hasSdkExtensions(VmService vm) async {
    for (final ref in (await vm.getVM()).isolates ?? const <IsolateRef>[]) {
      final isolate = await vm.getIsolate(ref.id!);
      if (isolate.extensionRPCs?.any(
            (e) => e.startsWith('ext.flutterpilot.'),
          ) ??
          false) {
        return true;
      }
    }
    return false;
  }

  /// A hot restart returns before the new isolate has run main(): until it
  /// has drawn its first frame (and, with the SDK, registered FlutterPilot's
  /// extensions), every tool would fail as "not registered". Waits up to
  /// 10 s; false if it never got there.
  static Future<bool> _waitForRestartedApp(
    VmService vm, {
    required bool sdk,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      try {
        for (final ref in (await vm.getVM()).isolates ?? const <IsolateRef>[]) {
          final isolate = await vm.getIsolate(ref.id!);
          final rpcs = isolate.extensionRPCs ?? const <String>[];
          if (sdk && !rpcs.any((e) => e.startsWith('ext.flutterpilot.'))) {
            continue;
          }
          if (!rpcs.contains('ext.flutter.didSendFirstFrameEvent')) continue;
          final res = await vm.callServiceExtension(
            'ext.flutter.didSendFirstFrameEvent',
            isolateId: ref.id,
          );
          if (res.json?['enabled'] == 'true') return true;
        }
      } catch (_) {
        // The old isolate may vanish mid-poll; try again.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }
}
