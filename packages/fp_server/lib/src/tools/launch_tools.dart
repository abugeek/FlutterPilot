part of '../../fp_server.dart';

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
          'Builds and starts the app (flutter run, or flutterpilot/launch.json'
          "'s command) on a device, waits for its first frame and connects; "
          'it outlives this session. Takes minutes: with the app running '
          'there it refuses unless relaunch:true (pubspec.yaml, assets or '
          'native code changed); hot_reload loads Dart changes in a second. '
          "A failed build returns its output's end.",
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
          'waitSeconds': JsonSchema.integer(
            description: 'Return early if still building (default 600).',
          ),
        },
      ),
      callback: (p, e) => _launchApp(p, e),
    );
  }

  CallToolResult _launchResult(String text, {bool isError = false}) =>
      CallToolResult(
        isError: isError,
        content: [TextContent(text: text)],
      );

  Future<CallToolResult> _launchApp(
    Map<String, dynamic> params, [
    RequestHandlerExtra? extra,
  ]) async {
    final relaunch = params['relaunch'] == true;
    final context = _activeContext;
    final connected = _vmService != null && context?.service != null;

    // Settled after the "already running" answer when the app's folder
    // cannot be told: that answer needs none of it.
    Directory? foundRoot;
    String? rootProblem;
    var hasConfig = false;
    var takesDevice = false;
    String? configDevice;
    try {
      final root = foundRoot = _launchRoot(params['project'] as String?);
      hasConfig = hasLaunchConfig(root);
      takesDevice = launchConfigTakesDevice(root);
      configDevice = launchConfigDevice(root);
    } on FormatException catch (e) {
      rootProblem = e.message;
    }
    final activeName = _fleetManager.activeDeviceId;
    final runningName = relaunch && connected && activeName != 'default'
        ? activeName
        : null;
    final asked = launchDevice(
      requested: params['device'] as String?,
      hasConfig: hasConfig,
      takesDevice: takesDevice,
      configDevice: configDevice,
      runningName: runningName,
    );
    // With no device named, "the app" is the connected one, as before.
    final runningHere = asked == null ? connected : await _isRunningOn(asked);

    if (runningHere && !relaunch) {
      final uri = asked == null ? _connectedUri! : _uriRunningOn(asked)!;
      final info = await probeDevice(
        uri,
      ).then<Object>((i) => i, onError: (_) => 'an app');
      final elsewhere = uri != _connectedUri;
      // When something a reload can't load did change, say so: this is
      // the case relaunch:true is for.
      final stale = elsewhere ? null : await _staleCodeNote();
      if (stale != null && stale.contains('launch_app(relaunch: true)')) {
        return _launchResult(
          'Already running and connected: $info. Nothing was launched. $stale',
          isError: true,
        );
      }
      return _launchResult(
        'Already running and connected: $info. Nothing was launched. '
        '${elsewhere ? 'It is not the active device: switch_device(id: "${_fleetManager.idForUri(uri) ?? asked}") targets it. ' : ''}'
        '${context?.buildMode == BuildMode.profile && !elsewhere ? 'It is a profile build (no hot reload): relaunch:true builds it again.' : 'hot_reload(restart: true) loads every changed Dart file and runs main() again in about a second.'} '
        'Pass relaunch:true only for what that cannot load: pubspec.yaml, '
        'assets, native code, dart-define/.env values, another device or '
        'mode. To run it on another device as well, pass that device.',
        isError: true,
      );
    }

    if (foundRoot == null) return _launchResult(rootProblem!, isError: true);
    final root = foundRoot;

    // A launch a previous call started is only waited for, as before: the
    // device is not chosen, `flutter devices` is not run and nothing is
    // stopped. Settled before the device question (review of PR #128).
    final inProgress = waitsForRunningLaunch(
      relaunch: relaunch,
      launchRunning: runningLaunchPid(root, device: asked) != null,
      connected: runningHere,
    );
    // Where this launch runs and what starts it, decided before the app it
    // replaces is stopped: a relaunch must not take it down for something
    // knowable up front (field test #346).
    final LaunchPlan plan;
    try {
      plan = await prepareLaunch(
        relaunch: relaunch,
        waitingForLaunch: inProgress,
        // A launch.json command without ${device} starts the app on its own
        // device, so there is nothing to choose or refuse.
        chooseDevice: !hasConfig || takesDevice,
        requested: asked,
        // Another app running elsewhere says nothing about this device.
        runningPlatform: connected && asked == null
            ? context?.operatingSystem
            : null,
        runningIsWeb: connected && (context?.isWeb ?? false),
        listDevices: flutterDeviceIds,
        commandFor: (device) => launchCommandFor(
          root,
          device: device,
          target: params['target'] as String?,
          mode: params['mode'] as String?,
        ),
        stop: () => _stopRunningApp(root, asked),
      );
    } on FormatException catch (e) {
      return _launchResult(e.message, isError: true);
    }
    if (plan.refusal != null) {
      return _launchResult(plan.refusal!, isError: true);
    }
    final command = plan.command!;
    final device = plan.device;
    // The name the files and the fleet entry carry: the planned device, or
    // the one the config starts.
    final name = device ?? asked;
    final ignored = command.fromConfig
        ? [
            for (final p in const ['device', 'target', 'mode'])
              if (params[p] != null && !(p == 'device' && takesDevice)) p,
          ]
        : const <String>[];
    final logFile = launchFileFor(launchLogFile, name);

    final log = File('${root.path}/$logFile');
    final waitFrom = DateTime.now();
    String? signingTeam;
    if (!inProgress) {
      // A stale URI file would be read as this launch's.
      try {
        File(
          '${root.path}/${launchFileFor(VmDiscoveryService.uriFile, name)}',
        ).deleteSync();
      } catch (_) {}
      try {
        final team = command.fromConfig
            ? null
            : await signingTeamFor(root, device: device);
        signingTeam = team;
        await startSupervised(
          root,
          command.command,
          device: name,
          environment: team == null
              ? null
              : {'FLUTTER_XCODE_DEVELOPMENT_TEAM': team},
        );
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
    final waitSeconds = (params['waitSeconds'] as num?)?.toInt();
    final wait = waitSeconds == null || waitSeconds <= 0
        ? _launchWait
        : Duration(seconds: waitSeconds.clamp(5, _launchWait.inSeconds));
    // The build takes minutes: a client that asked for progress sees the
    // phase, and one that resets its request timeout on progress keeps
    // waiting instead of cutting the call off at its own default.
    final progress = ToolProgress(extra);
    while (DateTime.now().difference(waitFrom) < wait) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // Cancelled: nobody reads this answer. The launch itself goes on, and
      // the next launch_app call waits for it without starting another.
      if (progress.cancelled) break;
      final text = readLog();
      uri = _launchUriFile(root, name) ?? vmServiceUriIn(text);
      if (uri != null && await _connectAs(name, uri)) break;
      uri = null;
      final code = launchExitCodeIn(text);
      if (code != null) {
        final phone = await phoneStateForDevice(device);
        final hint = explainLaunchFailure(text);
        return _launchResult(
          '"$command" exited with code $code before the app was up '
          '(in ${root.path}):\n${Redaction.text(launchLogTail(text))}'
          '${hint == null ? '' : '\nHINT: $hint'}'
          '${phone?.problem == null ? '' : '\nDEVICE: ${phone!.problem}. ${phone.fix}'}',
          isError: true,
        );
      }
      await progress.tick(
        'Building: ${launchPhase(text) ?? 'flutter run started'}',
      );
    }
    final seconds = DateTime.now().difference(waitFrom).inSeconds;
    if (uri == null) {
      return _launchResult(
        'Still building after $seconds s'
        '${launchPhase(readLog()) == null ? '' : ' (${launchPhase(readLog())})'}'
        '; the launch goes on. Call '
        'launch_app again to keep waiting (it will not start a second '
        'build). Output so far ($logFile):\n'
        '${Redaction.text(launchLogTail(readLog(), lines: 8))}',
      );
    }
    await progress.tick('Connected; waiting for the first frame');

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
      '${plan.deviceWasRunning || (runningName != null && asked == runningName) ? ' Relaunched on $name (the device it was running on).' : ''}'
      '${name != null && _fleetManager.deviceIds.length > 1 ? ' Registered as device "$name", now the active one; running: ${_fleetManager.deviceIds.join(', ')} (switch_device moves between them).' : ''}'
      '${drawn ? '' : ' It has not drawn its first frame yet: wait_for or get_app_summary in a moment.'}'
      '${ignored.isEmpty ? '' : ' ${ignored.join(', ')} not applied: $launchConfigFile sets the command.'}'
      '${signingTeam == null ? '' : ' Signed with team $signingTeam (the only Apple Development certificate on this Mac; set FLUTTER_XCODE_DEVELOPMENT_TEAM or a Team in Xcode to choose another).'}'
      '\nLeave it running: after editing Dart code call hot_reload. '
      'Build output: $logFile'
      '${relaunch ? ' (the app before it: ${launchFileFor(previousLaunchLogFile, name)})' : ''}.',
    );
  }

  /// Settles once the connected app has been checked for the SDK.
  Future<void>? get _sdkExtensionsReady;

  /// The URI `flutter run --vmservice-out-file` wrote for the launch on
  /// [device].
  String? _launchUriFile(Directory root, String? device) {
    final file = File(
      '${root.path}/${launchFileFor(VmDiscoveryService.uriFile, device)}',
    );
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

  /// The VM service URI of an app answering on [device]: its fleet entry,
  /// or a connected desktop app on that platform (found before it had a
  /// name, as "default").
  String? _uriRunningOn(String device) {
    final uri = _fleetManager.uriFor(device);
    if (uri != null) return uri;
    for (final MapEntry(key: id, value: c) in _deviceContexts.entries) {
      if (c.service != null &&
          deviceForPlatform(c.operatingSystem, isWeb: c.isWeb) == device) {
        return _fleetManager.uriFor(id) ?? c.uri;
      }
    }
    return null;
  }

  /// Whether an app answers on [device] now.
  Future<bool> _isRunningOn(String device) async {
    final uri = _uriRunningOn(device);
    if (uri == null) return false;
    return probeDevice(
      uri,
      timeout: const Duration(seconds: 2),
    ).then((_) => true, onError: (_) => false);
  }

  /// Connects to the app just launched on [device] as that fleet entry and
  /// makes it the active device; the apps on other devices keep running and
  /// stay registered. With no device, the connection the server had before.
  Future<bool> _connectAs(String? device, String uri) async {
    if (device == null) return _connectWithUri(uri);
    final normalized = normalizeVmServiceUri(uri) ?? uri;
    final before = _fleetManager.activeDeviceId;
    final previous = _fleetManager.registerDevice(device, normalized);
    if (previous != null) await _renameDeviceContext(previous, device);
    _fleetManager.switchDevice(device);
    if (await _connectWithUri(normalized)) {
      await _refreshToolVisibility();
      return true;
    }
    if (before != null && before != device && previous != before) {
      _fleetManager.switchDevice(before);
      await _connectWithUri(_fleetManager.uriFor(before));
    }
    return false;
  }

  /// Ends the app running on [device] (the connected one when null) and its
  /// launch command: asks the app to exit (flutter run then ends by itself,
  /// whoever started it), then stops a launch command of ours that is still
  /// there.
  Future<void> _stopRunningApp(Directory root, String? device) async {
    final uri = device == null ? _connectedUri : _uriRunningOn(device);
    final own = uri != null && uri != _connectedUri;
    VmService? vm = own ? null : _vmService;
    if (own) {
      try {
        vm = await connectVmService(uri);
      } catch (_) {}
    }
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
      if (own) unawaited(vm.dispose());
    }
    for (
      var i = 0;
      i < 20 && runningLaunchPid(root, device: device) != null;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final pid = runningLaunchPid(root, device: device);
    if (pid != null) {
      await killLaunchTree(pid);
      for (
        var i = 0;
        i < 20 && runningLaunchPid(root, device: device) != null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }
}
