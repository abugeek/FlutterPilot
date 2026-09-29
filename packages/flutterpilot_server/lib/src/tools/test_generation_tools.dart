part of '../../flutterpilot_server.dart';

/// Integration tests from what the agent did (ROADMAP §6): record from a
/// fresh start, write the test, run it, and only call it done if it passes.
mixin _TestGenerationToolsMixin
    on _FlutterPilotServerBase, _DevtoolsToolsMixin {
  void _registerTestGenerationTools() {
    _tool(
      'generate_test',
      description:
          'Turns what you do in the app into an integration_test. '
          'start:true restarts the app (hot restart) and records from there: '
          'taps, text, keys, scrolls, drags, back, assert_widget, wait_for '
          'and mock_http_response, with the widgets found by key, text or '
          'tooltip. name:"checkout" then writes '
          'integration_test/checkout_test.dart, runs it on the same device '
          'and reports whether it passed (with the failure if not). '
          'Obscured text is passed with --dart-define, never written. Takes '
          'minutes: the test builds the app again.',
      inputSchema: ToolInputSchema(
        properties: {
          'start': JsonSchema.boolean(
            description: 'Restart the app and start recording.',
          ),
          'name': JsonSchema.string(
            description:
                'Test name (letters, digits, _): stop recording, write and '
                'run the test.',
          ),
          'run': JsonSchema.boolean(
            description: 'Run the written test (default true).',
          ),
        },
      ),
      callback: (params, extra) async {
        CallToolResult text(String s, {bool error = false}) => CallToolResult(
          isError: error,
          content: [TextContent(text: s)],
        );
        if (params['start'] == true) return _startTestRecording(extra);
        final name = params['name']?.toString() ?? '';
        if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
          return text(
            'Pass start:true to begin recording, or name: a test name in '
            'lower_snake_case (e.g. "login_flow") to write and run it.',
            error: true,
          );
        }
        return _writeAndRunTest(name, run: params['run'] != false);
      },
    );
  }

  Future<CallToolResult> _startTestRecording(RequestHandlerExtra? extra) async {
    CallToolResult fail(String s) =>
        CallToolResult(isError: true, content: [TextContent(text: s)]);
    // The test starts the app from main(): so does the recording.
    final restart = _toolCallbacks['hot_reload'];
    if (restart != null && extra != null) {
      final res = await restart({'restart': true}, extra);
      if (res.isError == true) {
        return fail(
          'Could not restart the app to record from its start: '
          '${res.content.whereType<TextContent>().map((c) => c.text).join(' ')}',
        );
      }
    }
    // The restarted app registers its extensions again in a moment.
    _ExtensionResult? res;
    for (var i = 0; i < 20; i++) {
      res = await _callExtensionRaw('ext.flutterpilot.testRecording', {
        'action': 'start',
      });
      if (!res.isError) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (res == null || res.isError) {
      return fail(
        'The app did not start recording (does it use flutterpilot_sdk?): '
        '${res?.errorMessage}',
      );
    }
    _recordingTest = true;
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Recording from a fresh start of the app. Act and check as '
              'usual (tap_widget, enter_text, assert_widget, wait_for, '
              'mock_http_response…); then generate_test(name: "…") writes '
              'and runs the test. A hot restart before then loses the '
              'recording.',
        ),
      ],
    );
  }

  Future<CallToolResult> _writeAndRunTest(
    String name, {
    required bool run,
  }) async {
    CallToolResult fail(String s) =>
        CallToolResult(isError: true, content: [TextContent(text: s)]);
    final res = await _callExtensionRaw('ext.flutterpilot.testRecording', {
      'action': 'stop',
    });
    if (res.isError) return res.toCallToolResult();
    final wasRecording = _recordingTest;
    _recordingTest = false;
    final data = res.data!;
    final steps = [
      for (final s in (data['steps'] as List? ?? const []))
        (s as Map).cast<String, dynamic>(),
    ];
    final secrets = (data['secrets'] as List? ?? const []).cast<String>();
    if (steps.isEmpty) {
      return fail(
        wasRecording
            ? 'Nothing was recorded: the app restarted since '
                  'generate_test(start: true), or nothing was done. Start '
                  'again.'
            : 'Not recording: call generate_test(start: true) first, then '
                  'do the flow.',
      );
    }

    final context = await _deviceContextForParameters(const {});
    final vm = context?.service;
    if (vm == null) return fail('No running app.');
    final isolateId = await _uiIsolateId(vm, null);
    if (isolateId == null) return fail('No UI isolate.');
    final app = await _appEntrypoint(vm, isolateId);
    if (app == null) {
      return fail(
        "Could not tell the app's folder and entrypoint from its root "
        'library.',
      );
    }

    final test = writeIntegrationTest(
      name: name,
      mainImport: app.mainImport,
      steps: steps,
    );
    final file = File('${app.root}/integration_test/${name}_test.dart');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(test.source);
    await Process.run('dart', ['format', file.path]);
    final formatted = file.readAsStringSync();
    final relative = 'integration_test/${name}_test.dart';

    final notes = <String>[
      'Wrote $relative (${steps.length} steps).',
      if (test.skipped.isNotEmpty)
        'Not replayed (no test equivalent): ${test.skipped.join('; ')}.',
      if (test.unstable.isNotEmpty)
        'Found by position, so fragile: ${test.unstable.join('; ')} '
            '(a Key on those widgets makes the test stable).',
    ];
    final added = await _ensureIntegrationTestDependency(app.root);
    if (added != null) notes.add(added);
    if (!run) {
      return CallToolResult(content: [TextContent(text: notes.join('\n'))]);
    }

    final device = await _testDevice(context!.operatingSystem);
    if (device == null) {
      notes.add(
        'Not run: integration tests need a desktop, simulator or emulator '
        'target (this app runs on ${context.operatingSystem}).',
      );
      return CallToolResult(content: [TextContent(text: notes.join('\n'))]);
    }
    final started = DateTime.now();
    // Obscured text goes in a file only this user can read, not on the
    // command line where any process list shows it (security review).
    Directory? secretDir;
    File? secretFile;
    if (secrets.isNotEmpty) {
      secretDir = Directory.systemTemp.createTempSync('fp_secrets_');
      secretFile = File('${secretDir.path}/defines.json')
        ..writeAsStringSync(
          jsonEncode({
            for (var i = 0; i < secrets.length; i++)
              'FP_SECRET_${i + 1}': secrets[i],
          }),
        );
      if (!Platform.isWindows) {
        await Process.run('chmod', ['700', secretDir.path]);
        await Process.run('chmod', ['600', secretFile.path]);
      }
    }
    final ProcessResult result;
    try {
      result = await Process.run('flutter', [
        'test',
        relative,
        '-d',
        device,
        if (secretFile != null) '--dart-define-from-file=${secretFile.path}',
      ], workingDirectory: app.root).timeout(const Duration(minutes: 15));
    } on TimeoutException {
      return fail('${notes.join('\n')}\nThe test run took over 15 minutes.');
    } finally {
      try {
        secretDir?.deleteSync(recursive: true);
      } catch (_) {}
    }
    final seconds = DateTime.now().difference(started).inSeconds;
    final output = '${result.stdout}\n${result.stderr}';
    final passed = result.exitCode == 0;
    notes.add(
      passed
          ? 'Ran it on $device: passed ($seconds s).'
          : 'Ran it on $device: FAILED ($seconds s). Fix the test (or the '
                'app) and run: flutter test $relative -d $device\n'
                '${describeTestFailure(output, formatted, '${name}_test.dart')}',
    );
    if (context.operatingSystem != 'macos' &&
        context.operatingSystem != 'linux' &&
        context.operatingSystem != 'windows') {
      notes.add(
        'The test installed its own build of the app on the device: start '
        'the app again (flutter run) to keep driving it.',
      );
    }
    return CallToolResult(
      isError: !passed,
      content: [TextContent(text: notes.join('\n'))],
    );
  }

  /// The app's folder and its entrypoint as a package import.
  Future<({String root, String mainImport})?> _appEntrypoint(
    VmService vm,
    String isolateId,
  ) async {
    var uri = (await vm.getIsolate(isolateId)).rootLib?.uri;
    if (uri == null) return null;
    if (uri.startsWith('package:')) {
      final resolved = (await vm.lookupResolvedPackageUris(isolateId, [
        uri,
      ])).uris?.first;
      final path = resolved == null ? null : Uri.parse(resolved).path;
      final lib = path?.lastIndexOf('/lib/') ?? -1;
      if (path == null || lib < 0) return null;
      return (root: path.substring(0, lib), mainImport: uri);
    }
    if (!uri.startsWith('file:')) return null;
    final path = Uri.parse(uri).path;
    final lib = path.lastIndexOf('/lib/');
    if (lib < 0) return null;
    final root = path.substring(0, lib);
    final pubspec = File('$root/pubspec.yaml');
    if (!pubspec.existsSync()) return null;
    final name = RegExp(
      r'^name:\s*([A-Za-z0-9_]+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync())?.group(1);
    if (name == null) return null;
    return (root: root, mainImport: 'package:$name/${path.substring(lib + 5)}');
  }

  /// Adds `integration_test` to dev_dependencies when missing; says so.
  Future<String?> _ensureIntegrationTestDependency(String root) async {
    final pubspec = File('$root/pubspec.yaml').readAsStringSync();
    if (RegExp(r'^\s+integration_test:', multiLine: true).hasMatch(pubspec)) {
      return null;
    }
    final r = await Process.run('flutter', [
      'pub',
      'add',
      'dev:integration_test:{"sdk":"flutter"}',
    ], workingDirectory: root);
    return r.exitCode == 0
        ? 'Added integration_test (sdk: flutter) to dev_dependencies.'
        : 'Could not add integration_test to dev_dependencies: ${r.stderr}';
  }

  /// The `flutter test -d` id of the device the app runs on.
  Future<String?> _testDevice(String? operatingSystem) async {
    switch (operatingSystem) {
      case 'macos' || 'linux' || 'windows':
        return operatingSystem;
      case 'ios':
        return _crashTarget?.simulatorUdid;
      case 'android':
        try {
          final r = await Process.run('flutter', ['devices', '--machine']);
          final devices = (jsonDecode(r.stdout as String) as List)
              .cast<Map<String, dynamic>>();
          return devices
              .where((d) => '${d['targetPlatform']}'.startsWith('android'))
              .map((d) => d['id'] as String?)
              .firstOrNull;
        } catch (_) {
          return null;
        }
    }
    return null;
  }
}
