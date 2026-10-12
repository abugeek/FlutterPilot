part of '../../flutterpilot_server.dart';

/// launch_app: starts (or restarts from a new build) the app and connects.
mixin _LaunchToolsMixin on _FlutterPilotServerBase {
  /// Where to look for the app's project.
  List<Directory> get _discoveryRoots;

  /// How long one call waits for the build; the launch itself goes on.
  static const _launchWait = Duration(minutes: 10);

  void _registerLaunchTools() {
    _tool(
      'launch_app',
      description:
          'Builds and starts the app (flutter run, or the command in '
          'flutterpilot/launch.json), waits for its first frame and '
          'connects; the app outlives this session. Takes minutes: with an '
          'app already running it refuses unless relaunch:true (pubspec.yaml, '
          'assets or native code changed); hot_reload loads Dart changes in '
          'a second. A failed build returns the end of its output.',
      inputSchema: ToolInputSchema(
        properties: {
          'device': JsonSchema.string(
            description: 'flutter run -d: "macos", "chrome", an id.',
          ),
          'target': JsonSchema.string(
            description: 'Entrypoint (default lib/main.dart).',
          ),
          'mode': JsonSchema.string(
            enumValues: ['debug', 'profile'],
            description: 'Default debug.',
          ),
          'project': JsonSchema.string(description: 'App folder, if several.'),
          'relaunch': JsonSchema.boolean(
            description: 'Stop the running app and rebuild.',
          ),
        },
      ),
      callback: (p, e) => _launchApp(p),
    );
  }

  CallToolResult _launchResult(String text, {bool isError = false}) =>
      CallToolResult(
        isError: isError,
        content: [TextContent(text: text)],
      );

  Future<CallToolResult> _launchApp(Map<String, dynamic> params) async {
    final relaunch = params['relaunch'] == true;
    final context = _activeContext;
    final connected = _vmService != null && context?.service != null;

    if (connected && !relaunch) {
      final info = await probeDevice(
        _connectedUri!,
      ).then<Object>((i) => i, onError: (_) => 'an app');
      // When something a reload can't load did change, say so: this is
      // the case relaunch:true is for.
      final stale = await _staleCodeNote();
      if (stale != null && stale.contains('launch_app(relaunch: true)')) {
        return _launchResult(
          'Already running and connected: $info. Nothing was launched. $stale',
          isError: true,
        );
      }
      return _launchResult(
        'Already running and connected: $info. Nothing was launched. '
        '${context?.buildMode == BuildMode.profile ? 'It is a profile build (no hot reload): relaunch:true builds it again.' : 'hot_reload(restart: true) loads every changed Dart file and runs main() again in about a second.'} '
        'Pass relaunch:true only for what that cannot load: pubspec.yaml, '
        'assets, native code, dart-define/.env values, another device or '
        'mode.',
        isError: true,
      );
    }

    final Directory root;
    try {
      root = _launchRoot(params['project'] as String?);
    } on FormatException catch (e) {
      return _launchResult(e.message, isError: true);
    }
    final LaunchCommand command;
    try {
      command = launchCommandFor(
        root,
        device: params['device'] as String?,
        target: params['target'] as String?,
        mode: params['mode'] as String?,
      );
    } on FormatException catch (e) {
      return _launchResult(e.message, isError: true);
    }
    final ignored = command.fromConfig
        ? [
            for (final name in const ['device', 'target', 'mode'])
              if (params[name] != null) name,
          ]
        : const <String>[];

    final log = File('${root.path}/$launchLogFile');
    var inProgress = runningLaunchPid(root) != null && !connected;
    if (relaunch) {
      await _stopRunningApp(root);
      inProgress = false;
    }
    final waitFrom = DateTime.now();
    if (!inProgress) {
      // A stale URI file would be read as this launch's.
      try {
        File('${root.path}/${VmDiscoveryService.uriFile}').deleteSync();
      } catch (_) {}
      try {
        await startSupervised(root, command.command);
      } on ProcessException catch (e) {
        return _launchResult(
          'Could not start the launcher: ${e.message}',
          isError: true,
        );
      }
    }

    String readLog() {
      try {
        return log.readAsStringSync();
      } catch (_) {
        return '';
      }
    }

    String? uri;
    while (DateTime.now().difference(waitFrom) < _launchWait) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final text = readLog();
      uri = _launchUriFile(root) ?? vmServiceUriIn(text);
      if (uri != null && await _connectWithUri(uri)) break;
      uri = null;
      final code = launchExitCodeIn(text);
      if (code != null) {
        final phone = await phoneStateForDevice(params['device'] as String?);
        final hint = explainLaunchFailure(text);
        return _launchResult(
          '"$command" exited with code $code before the app was up '
          '(in ${root.path}):\n${Redaction.text(launchLogTail(text))}'
          '${hint == null ? '' : '\nHINT: $hint'}'
          '${phone?.problem == null ? '' : '\nDEVICE: ${phone!.problem}. ${phone.fix}'}',
          isError: true,
        );
      }
    }
    final seconds = DateTime.now().difference(waitFrom).inSeconds;
    if (uri == null) {
      return _launchResult(
        'Still building after $seconds s; the launch goes on. Call '
        'launch_app again to keep waiting (it will not start a second '
        'build). Output so far ($launchLogFile):\n'
        '${Redaction.text(launchLogTail(readLog(), lines: 8))}',
      );
    }

    await _sdkExtensionsReady;
    final vm = _vmService;
    final drawn =
        vm != null &&
        await _SelfHealToolsMixin._waitForRestartedApp(
          vm,
          sdk: _activeContext?.hasSdk == true,
        );
    final info = await probeDevice(
      _connectedUri ?? uri,
    ).then<Object>((i) => i, onError: (_) => 'the app');
    return _launchResult(
      '${inProgress ? 'The launch finished' : 'Launched'}: $info, connected '
      '($seconds s, "$command").'
      '${drawn ? '' : ' It has not drawn its first frame yet: wait_for or get_app_summary in a moment.'}'
      '${ignored.isEmpty ? '' : ' ${ignored.join(', ')} not applied: $launchConfigFile sets the command.'}'
      '\nLeave it running: after editing Dart code call hot_reload. '
      'Build output: $launchLogFile'
      '${relaunch ? ' (the app before it: $previousLaunchLogFile)' : ''}.',
    );
  }

  /// Settles once the connected app has been checked for the SDK.
  Future<void>? get _sdkExtensionsReady;

  /// The URI `flutter run --vmservice-out-file` wrote for this launch.
  String? _launchUriFile(Directory root) {
    final file = File('${root.path}/${VmDiscoveryService.uriFile}');
    try {
      if (!file.existsSync()) return null;
      final text = file.readAsStringSync().trim();
      return text.startsWith('http') || text.startsWith('ws') ? text : null;
    } catch (_) {
      return null;
    }
  }

  /// The app folder to launch in: [project] when given, the one `-p`
  /// names, or the only Flutter app under the workspace.
  Directory _launchRoot(String? project) {
    final apps = flutterAppsUnder(_discoveryRoots);
    if (project != null && project.isNotEmpty) {
      for (final app in apps) {
        if (app.path == Directory(project).absolute.path ||
            app.path.endsWith('/$project') ||
            app.path.endsWith('\\$project')) {
          return app;
        }
      }
      throw FormatException(
        'No Flutter app "$project" in the workspace. Found: '
        '${apps.isEmpty ? 'none' : apps.map((a) => a.path).join(', ')}.',
      );
    }
    if (apps.length == 1) return apps.single;
    if (apps.isEmpty) {
      throw FormatException(
        'No Flutter app (a pubspec.yaml with lib/main.dart) found under '
        '${_discoveryRoots.map((d) => d.path).join(', ')}. Start the '
        'server with -p <app folder>.',
      );
    }
    throw FormatException(
      'Several Flutter apps here; pass project: one of '
      '${apps.map((a) => a.path).join(', ')}.',
    );
  }

  /// Ends the running app and its launch command: asks the app to exit
  /// (flutter run then ends by itself, whoever started it), then stops a
  /// launch command of ours that is still there.
  Future<void> _stopRunningApp(Directory root) async {
    final vm = _vmService;
    if (vm != null) {
      try {
        for (final ref in (await vm.getVM()).isolates ?? const <IsolateRef>[]) {
          final rpcs = (await vm.getIsolate(ref.id!)).extensionRPCs ?? const [];
          if (!rpcs.contains('ext.flutter.exit')) continue;
          await vm
              .callServiceExtension('ext.flutter.exit', isolateId: ref.id)
              .timeout(const Duration(seconds: 2));
        }
      } catch (_) {
        // The app exiting drops the connection mid-call.
      }
    }
    for (var i = 0; i < 20 && runningLaunchPid(root) != null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final pid = runningLaunchPid(root);
    if (pid != null) {
      Process.killPid(pid);
      for (var i = 0; i < 20 && runningLaunchPid(root) != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }
}
