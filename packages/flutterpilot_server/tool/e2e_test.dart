import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterpilot_server/src/dtd_discovery.dart';
import 'package:flutterpilot_server/src/web_limits.dart';
import 'package:flutterpilot_server/src/zero_code.dart';

/// End-to-end test of the real agent path:
///   fresh `flutter create` app -> `flutterpilot init --local` -> `flutter run`
///   -> MCP server over stdio -> tools/call.
///
/// Usage (from packages/flutterpilot_server):
///   dart run tool/e2e_test.dart [-d <device>]   # default device: macos
///   dart run tool/e2e_test.dart --zero-code [-d <device>]
///   add --verbose to print every response
///
/// --zero-code runs a plain `flutter create` app without flutterpilot_sdk
/// and checks what an agent gets from Flutter's own inspector instead.
///
/// Covers: init wiring, widget tree, enter_text, press_key, secondary tap,
/// text scale and locale on an unwired MaterialApp,
/// pinch_zoom, interactive elements, covered-route assertions, tap_widget, Dio mock + network logs,
/// hot_reload applying an edited source file with state kept, hot restart.
Future<void> main(List<String> args) async {
  final d = args.indexOf('-d');
  final device = d >= 0 && d + 1 < args.length ? args[d + 1] : 'macos';
  final zeroCode = args.contains('--zero-code');
  // Prints every response in full, not only failures.
  final verbose = args.contains('--verbose');
  final isDesktop = const {'macos', 'linux', 'windows'}.contains(device);
  final isWeb = device == 'chrome' || device == 'web-server';
  final isMobile = !isDesktop && !isWeb;
  final isIos = isMobile && !device.startsWith('emulator');
  final repo = Directory.fromUri(Platform.script.resolve('../../..')).path;
  final serverDir = '${repo}packages/flutterpilot_server';
  final work = Directory.systemTemp.createTempSync('fp_e2e_');
  final app = '${work.path}/fixture';
  Process? flutter, server, copy;
  var failed = 0;
  // What the server and the app logged: a failed check prints what they
  // said while it ran, so a CI failure shows its cause.
  final serverLog = <String>[];
  final appLog = <String>[];
  ({int server, int app}) mark() =>
      (server: serverLog.length, app: appLog.length);
  void explain(({int server, int app}) from) {
    final said = serverLog
        .skip(from.server)
        .where((l) => !l.contains(' FINE ') && l.trim().isNotEmpty)
        .toList();
    final app = appLog.skip(from.app).toList();
    for (final (name, lines) in [('server', said), ('app', app)]) {
      if (lines.isEmpty) continue;
      print('   $name said:');
      for (final l in lines.skip(lines.length > 12 ? lines.length - 12 : 0)) {
        print('   | ${l.length > 200 ? '${l.substring(0, 200)}…' : l}');
      }
    }
  }

  Future<void> sh(String exe, List<String> a, {String? cwd}) async {
    // On Windows `flutter` is flutter.bat: only a shell finds it.
    final r = await Process.run(
      exe,
      a,
      workingDirectory: cwd,
      runInShell: Platform.isWindows,
    );
    if (r.exitCode != 0) {
      throw 'FAILED: $exe ${a.join(' ')}\n${r.stdout}\n${r.stderr}';
    }
  }

  /// What the Dart Tooling Daemon side looked like when discovery failed.
  Future<void> explainDtd() async {
    final watch = Stopwatch()..start();
    try {
      final r = await Process.run('dart', [
        'tooling-daemon',
        '--list',
        '--machine',
      ]).timeout(const Duration(seconds: 30));
      print(
        '   dart tooling-daemon --list --machine: exit ${r.exitCode} in '
                '${watch.elapsedMilliseconds} ms\n   | ${r.stdout}'
            .trimRight(),
      );
      if ('${r.stderr}'.trim().isNotEmpty) print('   | stderr: ${r.stderr}');
    } catch (e) {
      print(
        '   dart tooling-daemon --list: $e after ${watch.elapsedMilliseconds} ms',
      );
    }
    final home = Platform.environment['HOME'] ?? '';
    for (final dir in [
      '$home/Library/Application Support/Dart/dtd',
      '$home/.dart-tool/dtd',
    ]) {
      final d = Directory(dir);
      if (d.existsSync()) {
        print(
          '   $dir: ${d.listSync().map((e) => e.path.split('/').last).join(', ')}',
        );
      }
    }
    // `dart tooling-daemon` or its snapshot, dart_tooling_daemon.
    final ps = await Process.run('pgrep', ['-fl', 'tooling.daemon']);
    print(
      '   daemons running: ${'${ps.stdout}'.trim().replaceAll('\n', '; ')}',
    );
    for (final line in await DtdDiscovery.report([work])) {
      print('   | $line');
    }
  }

  try {
    print('▶ creating fixture app in $app');
    await sh('flutter', [
      'create',
      '-e',
      '--platforms=macos,ios,android,web,windows',
      'fixture',
    ], cwd: work.path);
    if (zeroCode) {
      File('$app/lib/main.dart').writeAsStringSync(_plainMain);
    } else {
      await sh('flutter', ['pub', 'add', 'dio'], cwd: app);
      await sh('dart', [
        'run',
        '${repo}packages/flutterpilot_cli/bin/flutterpilot.dart',
        'init',
        '--local',
        repo,
      ], cwd: app);
      File('$app/lib/main.dart').writeAsStringSync(_fixtureMain);
      await sh('flutter', ['pub', 'get'], cwd: app);
      await sh('dart', [
        'run',
        '${repo}packages/flutterpilot_cli/bin/flutterpilot.dart',
        'mcp',
        'install',
        '--client',
        'claude',
        '--local',
        repo,
      ], cwd: app);
    }

    print('▶ flutter run -d $device (first build can take a few minutes)');
    flutter = await Process.start(
      'flutter',
      [
        'run',
        '--machine',
        // What `flutterpilot dev` passes; lets a server find the app (§3.1).
        '--vmservice-out-file=.dart_tool/flutterpilot_vm_uri',
        '-d',
        device,
      ],
      workingDirectory: app,
      runInShell: Platform.isWindows,
    );
    final wsUri = Completer<String>();
    final started = Completer<void>();
    String? appId;
    flutter.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!line.startsWith('[{')) {
            appLog.add(line);
            return;
          }
          for (final e in (jsonDecode(line) as List).cast<Map>()) {
            final params = e['params'] as Map?;
            if (e['event'] == 'app.log' || e['event'] == 'daemon.logMessage') {
              appLog.add('${params?['log'] ?? params?['message']}');
            } else if (e['event'] == 'app.stop') {
              appLog.add('app.stop ${params ?? ''}');
            }
            if (e['event'] == 'app.debugPort' && !wsUri.isCompleted) {
              wsUri.complete(params!['wsUri'] as String);
              appId = params['appId'] as String?;
            }
            if (e['event'] == 'app.started' && !started.isCompleted) {
              started.complete();
            }
          }
        });
    flutter.stderr.transform(utf8.decoder).listen((text) {
      stderr.write(text);
      appLog.addAll(const LineSplitter().convert(text));
    });
    // A failed build ends flutter run; say so instead of waiting 20 minutes.
    unawaited(
      flutter.exitCode.then((code) {
        if (!wsUri.isCompleted) {
          wsUri.completeError('flutter run exited ($code) before the app ran');
        }
      }),
    );
    // First Gradle/Xcode builds on CI runners can take well over 10 minutes.
    final uri = await wsUri.future.timeout(const Duration(minutes: 20));
    await started.future.timeout(const Duration(minutes: 2));
    print('▶ app running at $uri');

    server = await Process.start('dart', [
      'run',
      'bin/flutterpilot_server.dart',
      '--uri',
      uri,
    ], workingDirectory: serverDir);
    final mcp = _Mcp(server);
    server.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(serverLog.add);
    await mcp.request('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'e2e', 'version': '1'},
    });
    mcp.notify('notifications/initialized');

    /// Calls [tool]; passes when it succeeds (or fails, if [expectError]) and
    /// its text contains every string in [contains]. Retries for [within].
    Future<void> check(
      String label,
      String tool, [
      Map<String, dynamic> a = const {},
      List<String> contains = const [],
      bool expectError = false,
      Duration within = Duration.zero,
      int? maxBytes,
    ]) async {
      final from = mark();
      final deadline = DateTime.now().add(within);
      String text;
      bool ok;
      do {
        final res = await mcp.request('tools/call', {
          'name': tool,
          'arguments': a,
        });
        final result = res['result'] as Map?;
        text = res['error'] != null
            ? '${res['error']}'
            : ((result?['content'] as List?) ?? [])
                  .map((c) => c['text'] ?? '')
                  .join('\n');
        final isError = res['error'] != null || result?['isError'] == true;
        final withinBudget = maxBytes == null || text.length <= maxBytes;
        ok =
            isError == expectError &&
            contains.every(text.contains) &&
            withinBudget;
        if (!ok && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      } while (!ok && DateTime.now().isBefore(deadline));
      if (!ok) failed++;
      final shown = verbose || text.length <= 300
          ? text
          : '${text.substring(0, 300)}…';
      print(
        '${ok ? '✅' : '❌'} $label (${text.length}b)'
        '${ok && !verbose ? '' : '\n   $shown'}',
      );
      if (!ok) explain(from);
    }

    /// Like [check], but passes only if the text contains none of [absent].
    Future<void> checkAbsent(
      String label,
      String tool,
      Map<String, dynamic> a,
      List<String> absent,
    ) async {
      final from = mark();
      final res = await mcp.request('tools/call', {
        'name': tool,
        'arguments': a,
      });
      final result = res['result'] as Map?;
      final text = ((result?['content'] as List?) ?? [])
          .map((c) => c['text'] ?? '')
          .join('\n');
      final ok =
          res['error'] == null &&
          result?['isError'] != true &&
          !absent.any(text.contains);
      if (!ok) failed++;
      print(
        '${ok ? '✅' : '❌'} $label (${text.length}b)'
        '${ok && !verbose ? '' : '\n   $text'}',
      );
      if (!ok) explain(from);
    }

    /// Polls get_app_summary until its "Viewport: WxH" has the orientation.
    Future<void> expectViewport(String label, {required bool landscape}) async {
      final from = mark();
      // Simulators on CI can take many seconds to rotate.
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      var seen = '';
      var ok = false;
      while (!ok && DateTime.now().isBefore(deadline)) {
        final res = await mcp.request('tools/call', {
          'name': 'get_app_summary',
          'arguments': {},
        });
        final text = ((res['result']?['content'] as List?) ?? [])
            .map((c) => c['text'] ?? '')
            .join();
        final m = RegExp(r'Viewport: (\d+)x(\d+)').firstMatch(text);
        if (m != null) {
          seen = m.group(0)!;
          final w = int.parse(m.group(1)!), h = int.parse(m.group(2)!);
          ok = landscape ? w > h : h > w;
        }
        if (!ok) await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (!ok) failed++;
      print('${ok ? '✅' : '❌'} $label ($seen)');
      if (!ok) explain(from);
    }

    // Web apps have no CPU profile or dart:io HTTP profile: not listed.
    if (isWeb && !zeroCode) {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      Set<String> listed;
      do {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        listed =
            ((await mcp.request('tools/list', {}))['result']['tools'] as List)
                .map((t) => t['name'] as String)
                .toSet();
      } while (listed.any(webUnsupportedTools.contains) &&
          DateTime.now().isBefore(deadline));
      final hidden = !listed.any(webUnsupportedTools.contains);
      if (!hidden) failed++;
      print(
        '${hidden ? '✅' : '❌'} web: ${webUnsupportedTools.join(', ')} not '
        'listed',
      );
    }

    if (zeroCode) {
      final expected = isWeb
          ? zeroCodeTools.difference(webUnsupportedTools)
          : zeroCodeTools;
      // The SDK check runs up to 5 s after connecting; then the list shrinks.
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      Set<String> listed;
      do {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        listed =
            ((await mcp.request('tools/list', {}))['result']['tools'] as List)
                .map((t) => t['name'] as String)
                .toSet();
      } while (listed.length != expected.length &&
          DateTime.now().isBefore(deadline));
      final listOk =
          listed.length == expected.length && listed.containsAll(expected);
      if (!listOk) failed++;
      print(
        '${listOk ? '✅' : '❌'} only zero-code tools listed (${listed.length})',
      );
      const settle = Duration(seconds: 10);
      await check(
        'summary says zero-code and shows the screen',
        'get_app_summary',
        {},
        ['zero-code', 'flutterpilot init', 'Details page', 'Tab B'],
        false,
        settle,
        4096,
      );
      await checkAbsent(
        'summary leaves out the covered route and hidden tab',
        'get_app_summary',
        {},
        ['Home page', 'Tab A'],
      );
      await check(
        'widget tree from the inspector',
        'get_widget_tree',
        {},
        ['DetailsPage', 'lib/main.dart:'],
        false,
        Duration.zero,
        16384,
      );
      await check('screenshot', 'capture_screenshot', {}, [
        'Screenshot captured',
      ]);
      await check(
        'SDK-only tool not callable',
        'tap_widget',
        {'target': 'Details page'},
        [],
        true,
      );
      await check('hot_reload', 'hot_reload');
      await checkAbsent(
        'hot reload clears the exception flag',
        'get_errors',
        {},
        ['since the last hot reload'],
      );
      await check(
        'print output captured',
        'get_debug_logs',
        {},
        ['details built'],
        false,
        const Duration(seconds: 5),
      );
      // Structured errors (Flutter.Error events) are off on web.
      if (!isWeb) {
        await check(
          'layout error with its source line',
          'get_errors',
          {},
          ['overflowed', 'lib/main.dart:'],
          false,
          const Duration(seconds: 5),
        );
      }
    } else {
      const settle = Duration(seconds: 10);
      await check(
        'app summary',
        'get_app_summary',
        {},
        [],
        false,
        settle,
        4096,
      );

      // Performance budgets (ROADMAP §10): the median of 5 calls after 2
      // untimed ones, as the client sees it. Exact on a local macOS run; CI runners and other
      // devices get 3× + 100 ms (an Android emulator's trivial read took
      // 64 ms once: noise, not a regression). Printed either way, with every
      // call's time and the error when it fails.
      final exact = device == 'macos' && Platform.environment['CI'] == null;
      int limit(int ms) => exact ? ms : ms * 3 + 100;
      for (final (label, tool, args, ms, bytes) in [
        ('trivial read', 'get_navigation_stack', <String, dynamic>{}, 20, null),
        ('trivial read', 'get_errors', <String, dynamic>{}, 20, null),
        ('find a widget', 'assert_widget', {'text': 'Version A'}, 20, null),
        ('widget tree', 'get_widget_tree', <String, dynamic>{}, 60, 8192),
        ('app summary', 'get_app_summary', <String, dynamic>{}, 80, null),
        ('tap + post-action state', 'tap_widget', {'key': 'count'}, 200, null),
      ]) {
        final times = <int>[];
        var size = 0;
        String? error;
        final from = mark();
        // The first calls after launch run unoptimized code (a tap: 1–2 s,
        // field test "Latency observed"); the budget is for the ones after.
        for (var i = -2; i < 5; i++) {
          final watch = Stopwatch()..start();
          final res = await mcp.request('tools/call', {
            'name': tool,
            'arguments': args,
          });
          if (i < 0) continue;
          times.add(watch.elapsedMilliseconds);
          final result = res['result'] as Map?;
          final text = ((result?['content'] as List?) ?? [])
              .map((c) => c['text'] ?? '')
              .join('\n');
          if (res['error'] != null) error = '${res['error']}';
          if (result?['isError'] == true) error = text;
          size = text.length;
        }
        final median = (times.toList()..sort())[2];
        final ok =
            error == null &&
            median <= limit(ms) &&
            (bytes == null || size <= bytes);
        if (!ok) failed++;
        print(
          '${ok ? '✅' : '❌'} budget: $label ($tool) ${median}ms '
          '(≤ ${limit(ms)}), ${size}b${bytes == null ? '' : ' (≤ $bytes)'}'
          '${ok ? '' : '\n   the 5 calls: ${times.join(', ')} ms'}'
          '${error == null ? '' : '\n   returned an error: $error'}',
        );
        if (!ok) explain(from);
      }

      // Parallel devices (ROADMAP §8): a second copy of the fixture (the
      // debug app flutter run built, started directly) is another device.
      // It has no taps yet, so after the same tap the counters differ.
      if (device == 'macos') {
        copy = await Process.start(
          '$app/build/macos/Build/Products/Debug/fixture.app/Contents/MacOS/fixture',
          [],
        );
        final copyUri = Completer<String>();
        copy.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((l) {
              final m = RegExp(r'listening on (http\S+)').firstMatch(l);
              if (m != null && !copyUri.isCompleted) {
                copyUri.complete(m.group(1));
              }
            });
        await check(
          'register a second copy of the app',
          'register_device',
          {
            'id': 'copy',
            'uri': await copyUri.future.timeout(
              const Duration(seconds: 60),
              onTimeout: () => 'ws://127.0.0.1:1/none=/ws',
            ),
          },
          ['Registered "copy"'],
        );
        await check(
          'run_on_devices runs one flow on both and shows the difference',
          'run_on_devices',
          {
            'steps': [
              {
                'tool': 'tap_widget',
                'arguments': {'key': 'count'},
              },
              {
                'tool': 'assert_widget',
                'arguments': {'text': 'Version A'},
              },
            ],
          },
          [
            'on 2 devices',
            '1. tap_widget (key: "count"): ✅ all',
            '2. assert_widget (text: "Version A"): ✅ all',
            'tappable on copy only: "Tapped 1"',
          ],
        );
        copy.kill();
      }

      // Platform-specific tools are listed only where they can work.
      final listed =
          ((await mcp.request('tools/list', {}))['result']['tools'] as List)
              .map((t) => t['name'] as String)
              .toSet();
      final nativeOk = isIos
          ? listed.contains('native_screenshot')
          : !listed.any((n) => n.startsWith('native_'));
      if (!nativeOk) failed++;
      print(
        '${nativeOk ? '✅' : '❌'} native tools '
        '${isIos ? 'listed on iOS' : 'hidden off iOS'} (${listed.length} tools)',
      );
      // Plugin tools only for plugins the app registered (the fixture: Dio).
      final pluginsOk =
          listed.contains('mock_http_response') &&
          !listed.contains('query_supabase_table') &&
          !listed.contains('get_state');
      if (!pluginsOk) failed++;
      print(
        '${pluginsOk ? '✅' : '❌'} plugin tools only for registered plugins',
      );
      // Simulator with idb (not on CI runners): native screen, backgrounding
      // and bringing the app back.
      if (listed.contains('native_open_app') &&
          listed.contains('native_describe_screen')) {
        await check('native_describe_screen', 'native_describe_screen', {}, [
          'Send',
          '→ tap (',
        ]);
        await check('native_screenshot is in points', 'native_screenshot', {}, [
          'in points',
        ]);
        await check('native_button HOME', 'native_button', {'button': 'HOME'});
        await check(
          'a backgrounded app is reported, not waited on',
          'get_app_summary',
          {},
          ['in the background', 'native_open_app'],
          true,
          const Duration(seconds: 5),
        );
        await check('native_open_app', 'native_open_app', {}, ['foreground']);
        await check(
          'app answers again after native_open_app',
          'assert_widget',
          {'target': 'Send'},
          [],
          false,
          settle,
        );
      }
      await check(
        'list_connected_devices shows auto-discovered default',
        'list_connected_devices',
        {},
        ['default'],
      );
      if (isDesktop) {
        await check(
          'rotation honest on desktop',
          'set_app_settings',
          {'orientation': 'landscape'},
          ['Not applicable on desktop', 'skipped'],
        );
      } else if (isMobile) {
        await check('rotate to landscape', 'set_app_settings', {
          'orientation': 'landscape',
        });
        await expectViewport('viewport is landscape', landscape: true);
        await check('rotate back to portrait', 'set_app_settings', {
          'orientation': 'portrait',
        });
        await expectViewport('viewport is portrait again', landscape: false);
      }
      await check(
        'TextField isEnabled is true',
        'get_widget_properties',
        {'key': "TextField['Name']"},
        ['"isEnabled":true'],
      );
      await check(
        'widget tree shows app widgets',
        'get_widget_tree',
        {},
        ['Home', 'Send'],
        false,
        Duration.zero,
        16384,
      );
      // ROADMAP §5.1: the Send button is created on line 90 of the fixture.
      await check(
        'inspect_widget names the source line',
        'inspect_widget',
        {'key': 'Send'},
        ['lib/main.dart:90:', 'Home lib/main.dart:'],
        false,
        Duration.zero,
        2048,
      );
      // ROADMAP §5.7: the audit reads the semantics tree (labels, order).
      await check(
        'audit_screen_health lists the screen reader order',
        'audit_screen_health',
        {},
        ['Screen reader order', '"Send"'],
      );
      await check('mock /ping', 'mock_http_response', {
        'urlPattern': '/ping',
        'statusCode': 200,
        'body': '{"ok":true}',
      });
      // A field's label targets the field itself (not the label Text).
      await check('enter text by field label', 'enter_text', {
        'target': 'Name',
        'text': 'Pilot',
      });
      // ROADMAP §5.2: the tap runs inside a CPU profile and still happens
      // (the next check sees its result on screen).
      if (isWeb) {
        print(
          '⏭ web VM does not support CPU/timeline profiling: '
          'profile_action skipped',
        );
        await check('tap Send', 'tap_widget', {'key': 'Send'});
      } else {
        await check(
          'profile_action profiles tap Send',
          'profile_action',
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'Send'},
            'durationMs': isDesktop ? 500 : 1500,
          },
          [
            'Profiled tap_widget',
            'running Dart on the UI isolate',
            'tap_widget result: Widget tapped',
            // ROADMAP §5.3: the frames the tap caused, from the VM timeline.
            'Frames: ',
            if (isDesktop) 'App widgets rebuilt in the window:',
          ],
          false,
          Duration.zero,
          4096,
        );
        await check(
          'profile_action refuses a non-action tool',
          'profile_action',
          {'tool': 'get_app_summary'},
          ['runs an action tool'],
          true,
        );
      }
      await check(
        'mocked response reached UI',
        'assert_widget',
        {'text': 'Hello, Pilot (200)'},
        [],
        false,
        const Duration(seconds: 5),
      );
      await check('network log has mocked call', 'get_network_logs', {}, [
        '/ping',
        '200',
      ]);
      // An argument the tool doesn't have is refused, not dropped (#280).
      await check(
        'an unknown argument is refused',
        'get_network_logs',
        {'clear': true},
        ['has no "clear" parameter', 'nothing was done'],
        true,
      );

      // Merged tools (ROADMAP §4.2): one tool, the mode chosen by a parameter.
      await check(
        'wait_for a widget',
        'wait_for',
        {'key': 'Send'},
        ['on screen'],
      );
      await check('wait_for needs a condition', 'wait_for', {}, [
        'Say what to wait for',
      ], true);
      await check(
        'enter_text "" clears the field',
        'enter_text',
        {'target': 'Name', 'text': ''},
        ['Cleared'],
      );
      await check(
        'dark theme',
        'set_app_settings',
        {'theme': 'dark'},
        ['✓ theme dark'],
      );
      await check('light theme', 'set_app_settings', {'theme': 'light'});
      // Text scale and locale act like the device settings: no wiring in the
      // fixture's plain MaterialApp (ROADMAP §3.12).
      await check(
        'text scale reaches an unwired app',
        'set_app_settings',
        {'textScale': 1.5},
        ['✓ text scale 1.5'],
      );
      await check('app shows scale 1.5', 'assert_widget', {
        'text': 'Scale 1.5',
      });
      await check(
        'text scale resets',
        'set_app_settings',
        {'textScale': 0},
        ['✓ text scale 0'],
      );
      await check('app shows scale 1.0', 'assert_widget', {
        'text': 'Scale 1.0',
      });
      await check(
        'locale reaches an unwired app',
        'set_app_settings',
        {'locale': 'en-GB'},
        ['✓ locale en-GB'],
      );
      await check('app shows en_GB', 'assert_widget', {'text': 'Locale en_GB'});
      await check(
        'unsupported locale is reported, not faked',
        'set_app_settings',
        {'locale': 'fr'},
        ['had no effect', 'does not support fr', 'en_US, en_GB'],
      );
      await check(
        'locale back to the device',
        'set_app_settings',
        {'locale': 'system'},
        ['✓ locale system'],
      );
      // The window is resized on the host. CI runners do not grant the
      // Accessibility access that needs, so the resize runs locally only.
      if (device == 'macos' && Platform.environment['CI'] == null) {
        await check(
          'window resizes to a narrower width',
          'set_app_settings',
          {'windowSize': '700x600'},
          ['✓ window 700x600', 'viewport now 700x'],
        );
        await check(
          'window resizes back',
          'set_app_settings',
          {'windowSize': '800x600'},
          ['viewport now 800x'],
        );
      } else if (device != 'macos') {
        await check(
          'window size is refused off macOS, not faked',
          'set_app_settings',
          {'windowSize': '700x600'},
          ['macOS desktop apps only'],
          true,
        );
      }
      await check(
        'a malformed window size is refused',
        'set_app_settings',
        {'windowSize': 'wide'},
        ['use WIDTHxHEIGHT'],
        true,
      );
      await check(
        'save baseline',
        'compare_screenshot',
        {'name': 'home', 'save': true},
        ['saved'],
      );
      await check(
        'compare with baseline',
        'compare_screenshot',
        {'name': 'home', 'threshold': 5},
        ['PASSED'],
      );
      // A tap that changes nothing: its 🤖 badge (700 ms) is not in the picture.
      await check('tap that changes nothing', 'tap_widget', {'key': 'card'});
      await check(
        'the tap badge is not in the screenshot',
        'compare_screenshot',
        {'name': 'home', 'threshold': 0.5},
        ['PASSED'],
      );
      await check(
        'open a dialog',
        'tap_widget',
        {'key': 'Dialog'},
        ['A dialog'],
      );
      await check(
        'a dialog is in the screenshot',
        'compare_screenshot',
        {'name': 'home', 'threshold': 5},
        ['FAILED'],
        true,
      );
      await check('close the dialog', 'tap_widget', {'key': 'Close dialog'});
      await check('assert_widget needs a check', 'assert_widget', {}, [
        'Say what to check',
      ], true);

      // Keyboard, context menu, pinch, discovery, and on-screen-only assertions.
      // enter_text focuses the field (the tap on Send above moved focus away).
      await check('focus field again', 'enter_text', {
        'key': "TextField['Name']",
        'text': 'Pilot',
      });
      await check('press_key enter submits field', 'press_key', {
        'key': 'enter',
      });
      // CI emulators can render the resulting frame a moment after the action.
      const react = Duration(seconds: 5);
      await check(
        'submit handled',
        'assert_widget',
        {'text': 'Submitted: Pilot'},
        [],
        false,
        react,
      );
      // Keyboard (ROADMAP §3.11): each key reaches the app once, and in a
      // text field editing keys edit it (desktop editing normally comes from
      // the OS input client, which synthesized key events never reach).
      await check('nothing focused', 'focus_widget', {});
      await check(
        'a key arrives once',
        'press_key',
        {'key': 'escape'},
        ['Key: Escape x1'],
      );
      await check('field for key editing', 'enter_text', {
        'key': "TextField['Name']",
        'text': 'Pilot',
      });
      await check(
        'backspace edits the field',
        'press_key',
        {'key': 'backspace'},
        ['Field: "Pilo" (cursor at 4)', 'Key: Backspace x1'],
      );
      await check(
        'a character is typed',
        'press_key',
        {'key': 'x'},
        ['Field: "Pilox"'],
      );
      await check(
        'arrow moves the cursor',
        'press_key',
        {'key': 'arrowLeft'},
        ['Field: "Pilox" (cursor at 4)'],
      );
      await check(
        'select all',
        'press_key',
        {
          'key': 'a',
          'modifiers': ['meta'],
        },
        ['selected 0–5'],
      );
      await check(
        'typing replaces the selection',
        'press_key',
        {'key': 'z'},
        ['Field: "z" (cursor at 1)'],
      );
      await check(
        'the app saw the edits',
        'get_widget_properties',
        {'key': "TextField['Name']"},
        ['"text":"z"'],
      );
      await check('secondary tap', 'tap_widget', {
        'key': 'card',
        'gesture': 'secondary',
      });
      await check(
        'context handler ran',
        'assert_widget',
        {'text': 'Context menu opened'},
        [],
        false,
        react,
      );
      await check('pinch_zoom', 'pinch_zoom', {
        'key': 'zoomable',
        'scale': 2.0,
      });
      await check(
        'zoom applied',
        'assert_widget',
        {'text': 'zoom 1.0'},
        [],
        true,
      );
      await check(
        'action chain accepts enter_text',
        'execute_action_chain',
        {
          'actions': [
            {'action': 'enter_text', 'target': 'Name', 'text': 'Pilot'},
          ],
        },
        ['1/1 steps done'],
      );
      await check(
        'action chain stops at a failed step',
        'execute_action_chain',
        {
          'actions': [
            {'action': 'tap', 'target': 'No such button'},
            {'action': 'enter_text', 'target': 'Name', 'text': 'never'},
          ],
        },
        ['stopped after 0/2', 'No such button', 'skipped'],
        true,
      );
      await check('interactive elements', 'get_interactive_elements', {}, [
        'Send',
        'card',
      ]);
      // Android shows text-selection handles after the key checks: they are
      // in the root Overlay, not part of MaterialApp's own UI.
      await checkAbsent(
        'no whole-app entry in the tappable list',
        'get_interactive_elements',
        {},
        ['"type":"MaterialApp"'],
      );
      // Errors (ROADMAP §3.10): a layout overflow is a bug to fix, not a
      // crash; an uncaught exception is flagged, with a small report that
      // points at the source line.
      //
      // The flag is app-wide. An exception from earlier in the run says
      // nothing about the overflow: on the CI iOS simulator the fixture's
      // AlertDialog once threw as it opened ('padding.isNonNegative': the
      // simulator reported negative view insets). Shown, not counted.
      final earlier =
          ((await mcp.request('tools/call', {
                        'name': 'get_errors',
                        'arguments': <String, dynamic>{},
                      }))['result']?['content']
                      as List? ??
                  [])
              .map((c) => c['text'] ?? '')
              .join('\n');
      final threwEarlier = earlier.contains('since the last hot reload');
      if (threwEarlier) {
        print(
          '${Platform.environment['CI'] == null ? '⚠️ ' : '::warning::'}'
          'an uncaught exception before the overflow check; "an overflow is '
          'not an uncaught exception" is skipped',
        );
        print('   ${earlier.replaceAll('\n', '\n   ')}');
      }
      await check('overflow the layout', 'tap_widget', {'key': 'Squeeze'});
      await check(
        'overflow is listed with its widget and line',
        'get_errors',
        {},
        ['overflowed', 'Row (lib/main.dart:'],
        false,
        react,
      );
      // ROADMAP §5.4: why it overflows, from the box inside it.
      await check(
        'inspect_widget layout explains the overflow',
        'inspect_widget',
        {'key': 'squeezed', 'layout': true},
        ['90×8', 'overflows by 50 px', 'need 90 px, it has 40 (width)'],
        false,
        Duration.zero,
        4096,
      );
      if (!threwEarlier) {
        await checkAbsent(
          'an overflow is not an uncaught exception',
          'get_errors',
          {},
          ['since the last hot reload'],
        );
      }
      await check('undo the overflow', 'tap_widget', {'key': 'Squeeze'});
      await check('throw from a button', 'tap_widget', {'key': 'Crash'});
      await check(
        'uncaught exception is flagged',
        'get_errors',
        {},
        ['Boom from the Crash button', 'since the last hot reload'],
        false,
        react,
      );
      await check(
        'crash report is small and names the source line',
        'get_errors',
        {'report': true},
        ['Boom from the Crash button', 'main.dart:', '## Route'],
        false,
        Duration.zero,
        2048,
      );
      await checkAbsent(
        'the stack is the app\'s, not FlutterPilot\'s',
        'get_errors',
        {},
        ['flutterpilot_sdk', 'asynchronous suspension', 'Widget Tree'],
      );

      // `target` works wherever `key` does.
      await check('target alias', 'assert_widget', {'target': 'Send'});
      // Post-action state waits for the page transition: it lists the new
      // page's back button, not the previous screen.
      await check(
        'open details',
        'tap_widget',
        {'key': 'Details'},
        ['Route changed', 'DetailsPage', 'Back'],
      );
      await check(
        'covered route is not "visible"',
        'assert_widget',
        {'text': 'Version A'},
        [],
        true,
        const Duration(seconds: 3), // after the page transition ends
      );
      await checkAbsent(
        'password is not echoed',
        'enter_text',
        {'target': 'PIN', 'text': 's3cret-pin'},
        ['s3cret-pin'],
      );
      // Security review: no read tool shows what is in a password field.
      for (final (tool, args) in [
        ('get_widget_tree', <String, dynamic>{}),
        ('get_widget_tree', <String, dynamic>{'diff': true}),
        ('get_app_summary', <String, dynamic>{}),
        ('get_interactive_elements', <String, dynamic>{}),
        ('get_semantics_tree', <String, dynamic>{}),
        ('get_widget_properties', <String, dynamic>{'key': 'PIN'}),
        ('get_debug_logs', <String, dynamic>{}),
        ('press_key', <String, dynamic>{'key': 'x'}),
      ]) {
        await checkAbsent(
          'password field hidden from $tool${args.isEmpty ? '' : ' $args'}',
          tool,
          args,
          ['s3cret-pin'],
        );
      }
      // Back waits for the pop transition and reports the new screen.
      await check(
        'back',
        'press_key',
        {'key': 'back'},
        ['Route changed', 'Send'],
      );
      await check(
        'home visible again',
        'assert_widget',
        {'text': 'Version A'},
        [],
        false,
        settle, // CI simulators can be slow to dismiss the keyboard and pop
      );
      // Security review: secrets the app logs and sends stay hidden.
      if (!isWeb) {
        await check('turn on HTTP profiling', 'get_http_profile', {'limit': 1});
      }
      await check('sign in (logs and sends secrets)', 'tap_widget', {
        'key': 'Sign in',
      });
      await Future<void>.delayed(const Duration(seconds: 3)); // the request
      const secrets = [
        'LOGSECRET1',
        'LOGSECRET2',
        'URLSECRET3',
        'BODYSECRET4',
        'HDRSECRET5',
      ];
      for (final (tool, args) in [
        ('get_debug_logs', <String, dynamic>{}),
        ('get_app_summary', <String, dynamic>{}),
        ('get_network_logs', <String, dynamic>{}),
        if (!isWeb) ...[
          ('get_http_profile', <String, dynamic>{'url': 'example.com/login'}),
          ('get_http_profile', <String, dynamic>{'id': 1}),
        ],
        ('get_errors', <String, dynamic>{}),
      ]) {
        await checkAbsent('secrets hidden from $tool', tool, args, secrets);
      }
      // Settle timing (ROADMAP §3.13): each response describes the screen
      // the action led to, not the one mid-animation or before a late push.
      await check(
        'navigation after a delay is in the tap response',
        'tap_widget',
        {'key': 'Later'},
        ['Route changed', 'DetailsPage', 'Back'],
      );
      await check(
        'back from the delayed page',
        'press_key',
        {'key': 'back'},
        ['Route changed', 'Send'],
      );
      // ROADMAP §5.5: opening and closing the details page leaks nothing
      // of the app's.
      if (isWeb) {
        print(
          '⏭ web VM does not support allocation profiles: leak check skipped',
        );
      } else {
        await check(
          'leak check: details page cycle keeps no app objects',
          'get_memory_details',
          {
            'cycle': [
              {
                'tool': 'tap_widget',
                'arguments': {'key': 'Details'},
              },
              {
                'tool': 'press_key',
                'arguments': {'key': 'back'},
              },
            ],
            'times': 3,
          },
          ['Leak check: 3 rounds', 'No app class leaks per round'],
          false,
          Duration.zero,
          4096,
        );
      }
      await check(
        'a drawer is read once it is open',
        'tap_widget',
        {'key': 'Drawer'},
        ['Tappable now', 'Drawer item'],
      );
      await check(
        'and once it is closed',
        'tap_widget',
        {'key': 'Drawer item'},
        ['Tappable now', 'Send'],
      );
      // ROADMAP §9: lazy lists. The page opens at Row ~400.
      await check(
        'open a long lazy list',
        'tap_widget',
        {'key': 'List'},
        ['Route changed', 'ListPage'],
      );
      await check(
        'a row the list has not built, above: "Row 3", not "Row 399"',
        'tap_widget',
        {'key': 'Row 3'},
      );
      await check('Row 3 was tapped', 'assert_widget', {
        'text': 'picked Row_3',
      });
      await check('a row further down', 'tap_widget', {'key': 'Row 480'});
      await check('Row 480 was tapped', 'assert_widget', {
        'text': 'picked Row_480',
      });
      await check(
        'a row that does not exist',
        'scroll_into_view',
        {'key': 'Row 9999'},
        ['Widget not found'],
        true,
      );
      // Pull to refresh answers with the refresh's result: on Android the
      // indicator animates into place before onRefresh even starts. (Not
      // scroll_into_view: it stops once Row 0 shows, not always at offset
      // 0, and a refresh only starts from there.)
      await check('to the top of the list', 'tap_widget', {
        'key': "Tooltip['Top']",
      });
      await check(
        'pull to refresh waits for the refresh',
        'swipe_widget',
        {'key': 'Row 0', 'direction': 'down'},
        ['Pulled to refresh', 'Refreshed 1'],
      );
      await check('back from the list', 'press_key', {'key': 'back'}, ['Send']);
      await check(
        'a tap that does nothing says so',
        'tap_widget',
        {'key': 'card'},
        // The quiet time is measured: 0.6 s on a slow runner.
        ['Nothing changed in the', 's after it either'],
      );

      // ROADMAP §5.6: an unmocked request goes out through dart:io and
      // shows in full (success or network error both have request headers).
      // Just before the hot reload: the fixture doesn't catch a 404, and the
      // reload clears that uncaught error for the checks after it.
      if (isWeb) {
        print(
          '⏭ web apps use browser networking rather than dart:io: '
          'HTTP profile check skipped',
        );
      } else {
        await check('clear the HTTP profile', 'get_http_profile', {
          'clear': true,
        });
        await check('clear the mock', 'mock_http_response', {'clear': true});
        await check('send for real', 'tap_widget', {'key': 'Send'});
        await check(
          'get_http_profile lists it by number',
          'get_http_profile',
          {'url': 'example.com/ping'},
          ['#1 [', 'GET https://example.com/ping'],
          false,
          const Duration(seconds: 15),
        );
        await check(
          'get_http_profile id shows it in full',
          'get_http_profile',
          {'id': 1},
          ['#1 GET https://example.com/ping', 'Request headers:'],
          false,
          Duration.zero,
          8192,
        );
        // Back to the mocked state the reload checks below expect.
        await check('mock /ping again', 'mock_http_response', {
          'urlPattern': '/ping',
          'statusCode': 200,
          'body': '{"ok":true}',
        });
        await check('send mocked again', 'tap_widget', {'key': 'Send'});
        await check(
          'mocked response on screen again',
          'assert_widget',
          {'text': 'Hello, Pilot (200)'},
          [],
          false,
          const Duration(seconds: 5),
        );
      }

      final main = File('$app/lib/main.dart');
      main.writeAsStringSync(
        main.readAsStringSync().replaceFirst('Version A', 'Version B'),
      );
      await check('hot_reload', 'hot_reload');
      await checkAbsent(
        'hot reload clears the exception flag',
        'get_errors',
        {},
        ['since the last hot reload'],
      );
      await check(
        'reload applied edited source',
        'assert_widget',
        {'text': 'Version B'},
        [],
        false,
        const Duration(seconds: 5),
      );
      await check('reload kept state', 'assert_widget', {
        'text': 'Hello, Pilot (200)',
      });

      await check('hot restart', 'hot_reload', {'restart': true});
      await check(
        'app back after restart',
        'assert_widget',
        {'text': 'Version B'},
        [],
        false,
        settle,
      );
      await check(
        'restart reset state',
        'assert_widget',
        {'text': 'Hello, Pilot'},
        [],
        true,
      );
    }

    // Fleet: name the app as flutter run prints its URI (http://.../), then
    // check that listing, switching and bad input are reported honestly.
    final sdkLabel = zeroCode ? 'zero-code' : 'flutterpilot_sdk';
    await check(
      'register_device renames the connected app',
      'register_device',
      {
        'id': 'e2e',
        'uri': uri
            .replaceFirst('ws://', 'http://')
            .replaceFirst(RegExp(r'ws$'), ''),
      },
      ['fixture · $sdkLabel', 'Was listed as "default"', 'active device'],
    );
    await check('list_connected_devices', 'list_connected_devices', {}, [
      '- e2e (active): ',
      'fixture · $sdkLabel',
    ]);
    await check(
      'register_device refuses an app that is not running',
      'register_device',
      {'id': 'gone', 'uri': 'ws://127.0.0.1:1/x=/ws'},
      ['Nothing was registered'],
      true,
    );
    await check(
      'switch_device to an unknown name',
      'switch_device',
      {'id': 'gone'},
      ['No device "gone"', '"e2e"'],
      true,
    );
    await check(
      'switch_device to the active device',
      'switch_device',
      {'id': 'e2e'},
      ['Already on "e2e"'],
    );
    await check(
      'a deviceId argument is refused, not ignored',
      'get_app_summary',
      {'deviceId': 'e2e'},
      ['switch_device(id: "e2e")'],
      true,
    );

    // A server the client starts outside the project, with no --uri or -p,
    // finds the app in the client's workspace folders (MCP roots).
    if (File('$app/.dart_tool/flutterpilot_vm_uri').existsSync()) {
      final elsewhere = Directory.systemTemp.createTempSync('fp_e2e_cwd_');

      /// Starts a server in an empty folder ([command], default `dart run`
      /// with no arguments); null when get_app_summary succeeds, else its
      /// error. Retries for a while when success is expected.
      Future<String?> summaryFromFreshServer({
        List<String>? roots,
        List<String>? command,
      }) async {
        final retry = roots != null || command != null;
        final cmd =
            command ??
            ['dart', 'run', '$serverDir/bin/flutterpilot_server.dart'];
        final p = await Process.start(
          cmd.first,
          cmd.skip(1).toList(),
          workingDirectory: elsewhere.path,
        );
        p.stderr.drain<void>();
        final m = _Mcp(
          p,
          onRequest: (method) => method == 'roots/list'
              ? {
                  'roots': [
                    for (final r in roots ?? const <String>[])
                      {'uri': Uri.directory(r).toString()},
                  ],
                }
              : null,
        );
        try {
          await m.request('initialize', {
            'protocolVersion': '2024-11-05',
            'capabilities': {'roots': ?(roots == null ? null : {})},
            'clientInfo': {'name': 'e2e-roots', 'version': '1'},
          });
          m.notify('notifications/initialized');
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          String text;
          bool ok;
          do {
            final res = await m.request('tools/call', {
              'name': 'get_app_summary',
              'arguments': {},
            });
            final result = res['result'] as Map?;
            text = ((result?['content'] as List?) ?? [])
                .map((c) => c['text'] ?? '')
                .join('\n');
            ok = res['error'] == null && result?['isError'] != true;
            if (!ok && retry) {
              await Future<void>.delayed(const Duration(milliseconds: 500));
            }
          } while (!ok && retry && DateTime.now().isBefore(deadline));
          return ok ? null : text;
        } finally {
          p.kill();
        }
      }

      final noRoots = await summaryFromFreshServer();
      final saysHow = noRoots != null && noRoots.contains('flutterpilot dev');
      if (!saysHow) failed++;
      print(
        '${saysHow ? '✅' : '❌'} outside the project without roots: '
        'says how to make the app findable${saysHow ? '' : '\n   $noRoots'}',
      );
      final withRoots = await summaryFromFreshServer(roots: [work.path]);
      if (withRoots != null) failed++;
      print(
        '${withRoots == null ? '✅' : '❌'} outside the project: finds the '
        "app in the client's workspace roots"
        '${withRoots == null ? '' : '\n   $withRoots'}',
      );
      // flutterpilot doctor reads what the running app registered (§3.4).
      final doctor = await Process.run(
        'dart',
        [
          'run',
          '${repo}packages/flutterpilot_cli/bin/flutterpilot.dart',
          'doctor',
          '-p',
          app,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final report = '${doctor.stdout}${doctor.stderr}';
      final expected = zeroCode
          ? ['App running (zero-code']
          : [
              '✅ SDK registered in the running app',
              '✅ flutterpilot_dio registered',
              '✅ MCP config: Claude Code',
              // init added it (the fixture supports macOS).
              '✅ macOS: network.client entitlement',
            ];
      final doctorOk =
          (zeroCode || doctor.exitCode == 0) && expected.every(report.contains);
      if (!doctorOk) failed++;
      print(
        '${doctorOk ? '✅' : '❌'} doctor sees the running app and what it '
        'registered${doctorOk ? '' : '\n   $report'}',
      );
      // The server exactly as `flutterpilot mcp install` configured it for
      // Claude Code (compiled executable, -p <app>).
      final installed = File('$app/.mcp.json');
      if (installed.existsSync()) {
        final entry =
            (jsonDecode(installed.readAsStringSync())
                    as Map)['mcpServers']['flutterpilot']
                as Map;
        final fromConfig = await summaryFromFreshServer(
          command: [
            entry['command'] as String,
            ...(entry['args'] as List).cast<String>(),
          ],
        );
        if (fromConfig != null) failed++;
        print(
          '${fromConfig == null ? '✅' : '❌'} the server "mcp install" wrote '
          'to .mcp.json drives the app'
          '${fromConfig == null ? '' : '\n   $fromConfig'}',
        );
        // ROADMAP §8 interop: the official Dart MCP server beside it, for
        // the code side only.
        final dartEntry =
            (jsonDecode(installed.readAsStringSync())
                    as Map)['mcpServers']['dart']
                as Map?;
        if (dartEntry != null) {
          final p = await Process.start(
            dartEntry['command'] as String,
            (dartEntry['args'] as List).cast<String>(),
            workingDirectory: app,
          );
          p.stderr.drain<void>();
          final m = _Mcp(
            p,
            onRequest: (method) => method == 'roots/list'
                ? {
                    'roots': [
                      {'uri': Uri.directory(app).toString()},
                    ],
                  }
                : null,
          );
          List<String> names = const [];
          try {
            await m.request('initialize', {
              'protocolVersion': '2025-06-18',
              'capabilities': {'roots': {}},
              'clientInfo': {'name': 'e2e-dart', 'version': '1'},
            });
            m.notify('notifications/initialized');
            final res = await m.request('tools/list', {});
            names = [
              for (final t
                  in ((res['result'] as Map?)?['tools'] as List? ?? const []))
                '${t['name']}',
            ];
          } finally {
            p.kill();
          }
          const duplicates = [
            'hot_reload',
            'hot_restart',
            'get_runtime_errors',
            'widget_inspector',
            'flutter_driver_command',
            'dtd',
          ];
          final split =
              names.contains('analyze_files') &&
              !names.any(duplicates.contains);
          if (!split) failed++;
          print(
            '${split ? '✅' : '❌'} the Dart MCP server "mcp install" added '
            'has the analyzer and none of the running-app tools'
            '${split ? '' : '\n   $names'}',
          );
        } else {
          print('⏭ this SDK has no Dart MCP server: interop check skipped');
        }
      }
      // A plain `flutter run` (or an IDE) writes no URI file: the app is
      // found through the Dart Tooling Daemon it registers with.
      final uriFile = File('$app/.dart_tool/flutterpilot_vm_uri');
      final hidden = uriFile.renameSync('${uriFile.path}.hidden');
      // The daemon keeps its own connection to the app (vm_service's 15 s
      // keep-alive) and forgets the app when that closes: on a stalled CI
      // simulator it then lists no app, and nothing can be found through it.
      final daemon = await DtdDiscovery.report([work]);
      final forgotten = daemon.any((l) => l.contains('"vmServices":[]'));
      if (forgotten) {
        print(
          '${Platform.environment['CI'] == null ? '⚠️ ' : '::warning::'}'
          'the Dart Tooling Daemon no longer lists the app; the two '
          'discovery checks through it are skipped',
        );
        for (final line in daemon) {
          print('   | $line');
        }
      }
      try {
        final viaDtd = forgotten
            ? null
            : await summaryFromFreshServer(roots: [work.path]);
        if (viaDtd != null) failed++;
        if (!forgotten) {
          print(
            '${viaDtd == null ? '✅' : '❌'} without the URI file: finds the '
            'app through the Dart Tooling Daemon'
            '${viaDtd == null ? '' : '\n   $viaDtd'}',
          );
        }
        if (viaDtd != null) await explainDtd();
        if (!zeroCode && !forgotten) {
          final doctor = await Process.run(
            'dart',
            [
              'run',
              '${repo}packages/flutterpilot_cli/bin/flutterpilot.dart',
              'doctor',
              '-p',
              app,
            ],
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
          );
          final report = '${doctor.stdout}${doctor.stderr}';
          final ok = report.contains('✅ SDK registered in the running app');
          if (!ok) failed++;
          print(
            '${ok ? '✅' : '❌'} doctor finds it the same way'
            '${ok ? '' : '\n   $report'}',
          );
        }
      } finally {
        hidden.renameSync(uriFile.path);
      }
      elsewhere.deleteSync(recursive: true);
    } else {
      print(
        '⏭ no .dart_tool/flutterpilot_vm_uri on $device: roots check skipped',
      );
    }

    // ROADMAP §8: verify a feature against criteria, with evidence.
    if (!zeroCode) {
      await check(
        'verify_feature starts',
        'verify_feature',
        {
          'feature': 'Greeting',
          'criteria': [
            'Send greets the user by name',
            'Send can be tapped twice',
          ],
        },
        ['1. Send greets the user by name'],
      );
      await check('verify: criterion 1', 'verify_feature', {'criterion': 1});
      await check('verify: mock /ping', 'mock_http_response', {
        'urlPattern': '/ping',
        'statusCode': 200,
        'body': '{"ok":true}',
      });
      await check('verify: name', 'enter_text', {
        'target': 'Name',
        'text': 'Verify',
      });
      await check('verify: send', 'tap_widget', {'key': 'Send'});
      await check(
        'verify: greeting',
        'assert_widget',
        {'text': 'Hello, Verify (200)'},
        const [],
        false,
        const Duration(seconds: 5),
      );
      await check(
        'verify: criterion 2',
        'verify_feature',
        {'criterion': 2},
        ['Criterion 1: ✅ PASS'],
      );
      await check('verify: send again, unchecked', 'tap_widget', {
        'key': 'Send',
      });
      await check(
        'verify_feature finish: pass needs a check',
        'verify_feature',
        {'finish': true},
        [
          'INCOMPLETE: 1 of 2 criteria passed, 1 not verified',
          '⚠️ NOT VERIFIED Send can be tapped twice',
          'report.md',
        ],
      );
      final reports = Directory('$app/flutterpilot/reports');
      final report = reports.existsSync()
          ? reports
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('report.md'))
                .firstOrNull
          : null;
      final ok =
          report != null &&
          report.readAsStringSync().contains(
            '| 1 | Send greets the user by '
            'name | ✅ PASS |',
          ) &&
          File('${report.parent.path}/criterion-1.png').existsSync();
      if (!ok) failed++;
      print(
        '${ok ? '✅' : '❌'} the report and its screenshots are written'
        '${ok ? '' : '\n   ${report?.readAsStringSync()}'}',
      );
    }

    // ROADMAP §7: a scenario brings its mocks back across a hot restart.
    if (!zeroCode) {
      await check('scenario: mock /ping', 'mock_http_response', {
        'urlPattern': '/ping',
        'statusCode': 202,
        'body': '{"ok":true}',
      });
      await check(
        'scenario save writes the file',
        'scenario',
        {'save': 'accepted', 'description': 'ping answers 202'},
        ['flutterpilot/scenarios/accepted.json', '1 mocked response(s)'],
      );
      if (isWeb) {
        print(
          '⏭ mocks do not survive a hot restart on web: '
          'scenario load check skipped',
        );
      } else {
        await check('scenario: clear the mock', 'mock_http_response', {
          'clear': true,
        });
        await check(
          'scenario load restarts with the mock active',
          'scenario',
          {'load': 'accepted'},
          ['Loaded scenario "accepted"', 'active from the first request'],
        );
        await check('scenario: enter a name', 'enter_text', {
          'target': 'Name',
          'text': 'Scenario',
        });
        await check('scenario: send', 'tap_widget', {'key': 'Send'});
        await check(
          "the scenario's mock answered",
          'assert_widget',
          {'text': 'Hello, Scenario (202)'},
          const [],
          false,
          const Duration(seconds: 5),
        );
      }
      await check('scenario list', 'scenario', {}, [
        '- accepted: ping answers 202',
      ]);

      // A plugin's native side, answered by a mock.
      await check(
        'mock_platform_channel answers a plugin call',
        'mock_platform_channel',
        {'channel': 'e2e/battery', 'method': 'level', 'result': 87},
        ['Mocked e2e/battery level: returns 87'],
      );
      await check('channel mock: tap Battery', 'tap_widget', {
        'key': 'Battery',
        'waitFor': 'Battery 87%',
      });
      await check(
        'mock_platform_channel lists the call and the mock',
        'mock_platform_channel',
        {},
        ['- e2e/battery level → 87', 'e2e/battery level — mocked'],
      );
      await check(
        'mock_platform_channel clear removes it',
        'mock_platform_channel',
        {'clear': true},
        ['Removed 1 mock(s)', 'No mocks.'],
      );
      await check('channel mock cleared: tap Battery', 'tap_widget', {
        'key': 'Battery 87%',
        'waitFor': 'Battery none',
      });
    }

    // ROADMAP §6: record a flow, write it as an integration_test, run it.
    if (isDesktop && !zeroCode) {
      await check(
        'generate_test starts recording from a restart',
        'generate_test',
        {'start': true},
        ['Recording from a fresh start'],
      );
      await check('recorded: mock /ping', 'mock_http_response', {
        'urlPattern': '/ping',
        'statusCode': 201,
        'body': '{"ok":true}',
      });
      await check('recorded: enter a name', 'enter_text', {
        'target': 'Name',
        'text': 'Recorded',
      });
      await check('recorded: send', 'tap_widget', {'key': 'Send'});
      await check(
        'recorded: the mocked greeting shows',
        'assert_widget',
        {'text': 'Hello, Recorded (201)'},
        const [],
        false,
        const Duration(seconds: 5),
      );
      await check(
        'generate_test writes the test and it passes',
        'generate_test',
        {'name': 'send_greeting'},
        ['Wrote integration_test/send_greeting_test.dart', 'passed'],
      );
      final written = File('$app/integration_test/send_greeting_test.dart');
      final source = written.existsSync() ? written.readAsStringSync() : '';
      final idiomatic = [
        "import 'package:fixture/main.dart' as app;",
        "DioPilotInterceptor.mock('/ping', statusCode: 201",
        "find.widgetWithText(TextField, 'Name')",
        "find.text('Send')",
      ].every(source.contains);
      if (!idiomatic) failed++;
      print(
        '${idiomatic ? '✅' : '❌'} the test uses the app, the mock and '
        'plain finders${idiomatic ? '' : '\n   $source'}',
      );
    }

    // ROADMAP §5.8: a native crash is reported with its reason, not just
    // "not running" (macOS files a report for a SIGABRT from outside too).
    final pgrep = device == 'macos'
        ? await Process.run('pgrep', ['-f', 'fixture.app/Contents/MacOS/'])
        : null;
    final pid = int.tryParse('${pgrep?.stdout}'.trim().split('\n').first);
    if (pid != null) {
      Process.killPid(pid, ProcessSignal.sigabrt);
      await check(
        'a native crash is reported when the app dies',
        'get_errors',
        {},
        ['The app crashed in native code', 'call get_errors again'],
        true,
        const Duration(seconds: 20),
      );
      appId = null; // nothing left to stop
    }

    if (appId != null) {
      flutter.stdin.writeln(
        jsonEncode([
          {
            'id': 1,
            'method': 'app.stop',
            'params': {'appId': appId},
          },
        ]),
      );
      await flutter.exitCode.timeout(
        const Duration(seconds: 20),
        onTimeout: () => 0,
      );
    }
  } catch (e) {
    failed++;
    print('❌ $e');
  } finally {
    copy?.kill();
    server?.kill();
    flutter?.kill();
    work.deleteSync(recursive: true);
  }
  print(failed == 0 ? '\nE2E passed' : '\nE2E: $failed failed');
  exit(failed == 0 ? 0 : 1);
}

/// Minimal line-delimited JSON-RPC client for the MCP stdio transport.
class _Mcp {
  /// [onRequest] answers requests the server sends (e.g. `roots/list`).
  _Mcp(this._p, {Map<String, dynamic>? Function(String method)? onRequest}) {
    _p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      try {
        final msg = jsonDecode(line) as Map<String, dynamic>;
        if (msg['method'] is String && msg.containsKey('id')) {
          final result = onRequest?.call(msg['method'] as String);
          _p.stdin.writeln(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': msg['id'],
              if (result != null)
                'result': result
              else
                'error': {'code': -32601, 'message': 'not supported'},
            }),
          );
          return;
        }
        _pending.remove(msg['id'])?.complete(msg);
      } catch (_) {}
    });
  }

  final Process _p;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  var _id = 0;

  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = ++_id;
    final c = _pending[id] = Completer();
    _p.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    // generate_test builds and runs an integration test: minutes.
    return c.future.timeout(
      const Duration(minutes: 10),
      onTimeout: () => {'error': 'timeout'},
    );
  }

  void notify(String method) =>
      _p.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': method}));
}

const _fixtureMain = r'''
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterpilot_dio/flutterpilot_dio.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

late final Dio dio;

void main() {
  FlutterPilot.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  dio = Dio()..interceptors.add(DioPilotInterceptor());
  runApp(MaterialApp(
    navigatorObservers: [NavigationTracker()],
    supportedLocales: const [Locale('en', 'US'), Locale('en', 'GB')],
    home: const Home(),
  ));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _name = TextEditingController();
  final _zoom = TransformationController();
  String _greeting = '';
  String _submitted = '';
  String _menu = '';
  String _zoomed = 'zoom 1.0', _battery = 'Battery';
  bool _squeeze = false;
  int _taps = 0;
  final _keyDowns = <String, int>{};
  String _lastKey = '';

  // Counts key-downs as the app sees them: press_key must deliver each once.
  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent) {
      setState(() {
        _lastKey = e.logicalKey.keyLabel;
        _keyDowns[_lastKey] = (_keyDowns[_lastKey] ?? 0) + 1;
      });
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  Future<void> _send() async {
    final res = await dio.get('https://example.com/ping');
    setState(() => _greeting = 'Hello, ${_name.text} (${res.statusCode})');
  }

  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) => Scaffold(
    key: _scaffold,
    drawer: Drawer(
      child: SafeArea(
        child: TextButton(
          onPressed: () => _scaffold.currentState!.closeDrawer(),
          child: const Text('Drawer item'),
        ),
      ),
    ),
    body: Column(children: [
      const Text('Version A'),
      // What set_app_settings(textScale/locale) reached, with no wiring above.
      // toStringAsFixed: on web 1.0.toString() is "1".
      Text('Scale ${(MediaQuery.textScalerOf(context).scale(10) / 10).toStringAsFixed(1)}'),
      Text('Locale ${Localizations.localeOf(context)}'),
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => setState(() => _submitted = 'Submitted: $v'),
      ),
      ElevatedButton(onPressed: _send, child: const Text('Send')),
      Text(_greeting),
      Text(_submitted),
      GestureDetector(
        key: const ValueKey('card'),
        behavior: HitTestBehavior.opaque,
        onSecondaryTap: () => setState(() => _menu = 'Context menu opened'),
        child: const Padding(padding: EdgeInsets.all(12), child: Text('Right-click me')),
      ),
      Text(_menu),
      InteractiveViewer(
        key: const ValueKey('zoomable'),
        transformationController: _zoom,
        onInteractionEnd: (_) => setState(
          () => _zoomed = 'zoom ${_zoom.value.getMaxScaleOnAxis().toStringAsFixed(1)}',
        ),
        child: const SizedBox(width: 200, height: 100, child: ColoredBox(color: Colors.blue)),
      ),
      Text(_zoomed),
      ElevatedButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DetailsPage(),
          ),
        ),
        child: const Text('Details'),
      ),
      Wrap(children: [
        // Navigates after a short "request": the tap's response should
        // still show the page it led to.
        TextButton(
          onPressed: () async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            if (!context.mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DetailsPage()),
            );
          },
          child: const Text('Later'),
        ),
        TextButton(
          onPressed: () => _scaffold.currentState!.openDrawer(),
          child: const Text('Drawer'),
        ),
        TextButton(
          onPressed: () => throw StateError('Boom from the Crash button'),
          child: const Text('Crash'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ListPage()),
          ),
          child: const Text('List'),
        ),
        TextButton(
          onPressed: () => setState(() => _squeeze = !_squeeze),
          child: const Text('Squeeze'),
        ),
        TextButton(
          key: const ValueKey('count'),
          onPressed: () => setState(() => _taps++),
          child: Text('Tapped $_taps'),
        ),
        TextButton(onPressed: _signIn, child: const Text('Sign in')),
        // A plugin call no test host answers: mock_platform_channel does.
        TextButton(
          onPressed: () async {
            String text;
            try {
              final level = await const MethodChannel('e2e/battery')
                  .invokeMethod<int>('level');
              text = 'Battery $level%';
            } on MissingPluginException {
              text = 'Battery none';
            }
            setState(() => _battery = text);
          },
          child: Text(_battery),
        ),
        // On the root navigator, above the page: in screenshots too.
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('A dialog'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close dialog'),
                ),
              ],
            ),
          ),
          child: const Text('Dialog'),
        ),
        Text('Key: $_lastKey x${_keyDowns[_lastKey] ?? 0}'),
        if (_squeeze)
          const SizedBox(width: 40, child: Row(children: [SizedBox(key: ValueKey('squeezed'), width: 90, height: 8)])),
      ]),
    ]),
  );

  // Secrets in a log line, a URL, a header and a body: no tool may show
  // them (the security review's redaction sweep).
  Future<void> _signIn() async {
    debugPrint('signing in with api_key=LOGSECRET1 password: LOGSECRET2');
    try {
      await dio.post(
        'https://example.com/login?api_key=URLSECRET3&page=1',
        data: {'user': 'pilot', 'password': 'BODYSECRET4'},
        options: Options(headers: {'Authorization': 'Bearer HDRSECRET5'}),
      );
    } catch (_) {}
  }
}

/// A lazy list opened near Row 400: "Row 3" is not built yet, and the rows
/// on screen contain "Row 3" ("Row 399").
class ListPage extends StatefulWidget {
  const ListPage({super.key});
  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  final _rows = ScrollController(initialScrollOffset: 22300);
  String _picked = 'none';
  int _refreshed = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    // Underscores: the title must not match a row's label.
    appBar: AppBar(
      title: Text('picked ${_picked.replaceAll(' ', '_')}'),
      actions: [
        Text('Refreshed $_refreshed'),
        // To the very top: a pull to refresh starts only there.
        IconButton(
          tooltip: 'Top',
          onPressed: () => _rows.jumpTo(0),
          icon: const Icon(Icons.vertical_align_top),
        ),
      ],
    ),
    // A refresh that takes a moment, as a request would.
    body: RefreshIndicator(
      onRefresh: () async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        setState(() => _refreshed++);
      },
      child: ListView.builder(
        controller: _rows,
        itemCount: 500,
        itemBuilder: (_, i) => ListTile(
          title: Text('Row $i'),
          onTap: () => setState(() => _picked = 'Row $i'),
        ),
      ),
    ),
  );
}

class DetailsPage extends StatelessWidget {
  const DetailsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Details page')),
    body: const TextField(
      obscureText: true,
      decoration: InputDecoration(labelText: 'PIN'),
    ),
  );
}
''';

/// A plain app: no flutterpilot_sdk. It opens a page over the home page on
/// start; that page has a hidden IndexedStack child and a layout overflow.
const _plainMain = r'''
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: Home()));

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const DetailsPage()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Home page')));
}

class DetailsPage extends StatelessWidget {
  const DetailsPage({super.key});
  @override
  Widget build(BuildContext context) {
    print('details built');
    return Scaffold(
      appBar: AppBar(title: const Text('Details page')),
      body: Column(children: [
        const IndexedStack(index: 1, children: [Text('Tab A'), Text('Tab B')]),
        Row(children: [
          for (var i = 0; i < 40; i++) const Text('overflowing text '),
        ]),
      ]),
    );
  }
}
''';
