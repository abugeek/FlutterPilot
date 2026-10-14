part of '../../flutterpilot_server.dart';

/// Tools for self-heal status, reproduction tests, diagnostics, and hot reload/restart.
mixin _SelfHealToolsMixin on _FlutterPilotServerBase {
  void _registerSelfHealTools() {
    _tool(
      'hot_reload',
      description:
          'Recompiles edited .dart files and hot reloads them into the running '
          'app, keeping state. restart:true does a hot restart instead (state '
          'is reset) — needed for main(), initState, global/static '
          'initializers, enums, generic type changes and provider '
          'definitions. A restart loads every changed Dart file: use it '
          'after a git checkout or for a stuck app instead of rebuilding '
          '(needed only for pubspec.yaml, assets or native code). '
          'Needs an app started by `flutter run` or an IDE debug session.',
      inputSchema: ToolInputSchema(
        properties: {
          'restart': JsonSchema.boolean(
            description: 'Hot restart instead of hot reload.',
          ),
        },
      ),
      callback: (p, e) => _activeContext?.buildMode == BuildMode.profile
          ? Future.value(
              CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text:
                        'This is a profile build: compiled ahead of time, so '
                        'no hot reload or restart. Rebuild with "flutter run '
                        '--profile" after editing, or use a debug build '
                        '("flutter run") to iterate.',
                  ),
                ],
              ),
            )
          : p['restart'] == true
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
    ({String root, int? logOffset, DateTime since})? before;
    try {
      // These reads do not depend on each other: started together, and the
      // ping below decides whether the others matter.
      final beforeFuture = _beforeReload(vmService, context);
      final sdkFuture = service == 'hotRestart'
          ? _hasSdkExtensions(vmService).catchError((_) => false)
          : Future.value(false);
      final isolateId = (await vmService.getVM()).isolates?.firstOrNull?.id;
      // A hot restart of an app stuck in a loop made flutter_tools wait its
      // full two minutes, then blamed a compile error. Ask the UI isolate
      // something first: no answer means it cannot take a reload now.
      if (!await _uiAnswers(vmService)) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text:
                  'No answer from the app within 5 s, so it cannot take a '
                  'hot ${service == 'hotRestart' ? 'restart' : 'reload'} '
                  'now; nothing was reloaded.',
            ),
          ],
        );
      }
      before = await beforeFuture;
      final hadSdk = await sdkFuture;
      await vmService
          .callMethod(method, isolateId: isolateId)
          .timeout(const Duration(minutes: 2));
      _selfHealManager.reset();
      context.lastReload = DateTime.now();
      if (service == 'hotRestart' &&
          !await _waitForRestartedApp(vmService, sdk: hadSdk)) {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  '$successText\nThe restart worked, but the app is still '
                  'starting: no first frame'
                  '${hadSdk ? ' or FlutterPilot registration' : ''} after '
                  '${_restartWait.inSeconds} s (a main() that awaits a lot '
                  'before runApp). Do not run the app again: call '
                  'wait_for or get_app_summary in a moment; get_debug_logs '
                  'shows what main() is waiting on if it never comes up.',
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
            text: reloadFailureText(
              service,
              details,
              compileErrors: before != null && mayBeCompileError(details)
                  ? await _compileErrors(before)
                  : '',
            ),
          ),
        ],
        isError: true,
      );
    }
  }

  /// Where to look for compiler errors if the reload about to run fails:
  /// the app's folder, how long launch_app's log of `flutter run` is now,
  /// and since when an edited file is news. Null when the app's folder
  /// can't be told.
  Future<({String root, int? logOffset, DateTime since})?> _beforeReload(
    VmService vm,
    DeviceRuntimeContext context,
  ) async {
    try {
      for (final ref in (await vm.getVM()).isolates ?? const <IsolateRef>[]) {
        final isolate = await vm.getIsolate(ref.id!);
        var uri = isolate.rootLib?.uri;
        if (uri != null && uri.startsWith('package:')) {
          uri = (await vm.lookupResolvedPackageUris(ref.id!, [
            uri,
          ])).uris?.first;
        }
        if (uri == null || !uri.startsWith('file:')) continue;
        final root = projectRootOfFile(Uri.parse(uri).toFilePath());
        if (root == null) continue;
        final log = File('$root/$launchLogFile');
        final started = isolate.startTime;
        return (
          root: root,
          logOffset:
              runningLaunchPid(Directory(root)) != null && log.existsSync()
              ? log.lengthSync()
              : null,
          since:
              context.lastReload ??
              (started == null
                  ? DateTime.now().subtract(const Duration(hours: 1))
                  : DateTime.fromMillisecondsSinceEpoch(started)),
        );
      }
    } catch (_) {}
    return null;
  }

  /// The compiler's errors for a reload that just failed: from the
  /// `flutter run` output when launch_app started the app, else from
  /// `dart analyze` on the Dart files edited since the last good reload.
  Future<String> _compileErrors(
    ({String root, int? logOffset, DateTime since}) before,
  ) async {
    final offset = before.logOffset;
    if (offset != null) {
      final log = File('${before.root}/$launchLogFile');
      // The supervisor copies flutter run's output a moment after it prints.
      for (var i = 0; i < 6; i++) {
        try {
          final bytes = log.readAsBytesSync();
          final errors = compileErrorsIn(
            utf8.decode(
              bytes.sublist(offset.clamp(0, bytes.length)),
              allowMalformed: true,
            ),
          );
          if (errors.isNotEmpty) return errors;
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    final files = dartFilesChangedSince(before.root, before.since);
    if (files.isEmpty) return '';
    try {
      final result = await runProgram([
        'dart',
        'analyze',
        '--format=machine',
        ...files,
      ], workingDirectory: before.root).timeout(const Duration(seconds: 30));
      return analyzerErrorsIn(
        '${result.stdout}\n${result.stderr}',
        before.root,
      );
    } catch (_) {
      return '';
    }
  }

  /// Whether the Flutter UI isolate answers a service extension within 5 s.
  /// True when there is nothing to ask yet (an app still starting).
  static Future<bool> _uiAnswers(VmService vm) async {
    try {
      for (final ref in (await vm.getVM()).isolates ?? const <IsolateRef>[]) {
        final rpcs = (await vm.getIsolate(ref.id!)).extensionRPCs ?? const [];
        if (!rpcs.contains('ext.flutter.didSendFirstFrameEvent')) continue;
        await vm
            .callServiceExtension(
              'ext.flutter.didSendFirstFrameEvent',
              isolateId: ref.id,
            )
            .timeout(const Duration(seconds: 5));
        return true;
      }
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return true;
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

  /// How long a restarted app gets to draw its first frame: a real app's
  /// main() (Firebase, a database, a session) took over 10 s, and the "not
  /// yet" answer read as a failed restart.
  static const _restartWait = Duration(seconds: 30);

  /// A hot restart returns before the new isolate has run main(): until it
  /// has drawn its first frame (and, with the SDK, registered FlutterPilot's
  /// extensions), every tool would fail as "not registered". Waits up to
  /// [_restartWait]; false if it never got there.
  static Future<bool> _waitForRestartedApp(
    VmService vm, {
    required bool sdk,
  }) async {
    final deadline = DateTime.now().add(_restartWait);
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
