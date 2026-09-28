import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  final repo = Directory.fromUri(Platform.script.resolve('../../..')).path;
  final serverDir = '${repo}packages/flutterpilot_server';
  final work = Directory.systemTemp.createTempSync('fp_e2e_');
  final app = '${work.path}/fixture';
  Process? flutter, server;
  var failed = 0;

  Future<void> sh(String exe, List<String> a, {String? cwd}) async {
    final r = await Process.run(exe, a, workingDirectory: cwd);
    if (r.exitCode != 0) {
      throw 'FAILED: $exe ${a.join(' ')}\n${r.stdout}\n${r.stderr}';
    }
  }

  try {
    print('▶ creating fixture app in $app');
    await sh('flutter', [
      'create',
      '-e',
      '--platforms=macos,ios,android,web',
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
    }

    print('▶ flutter run -d $device (first build can take a few minutes)');
    flutter = await Process.start('flutter', [
      'run',
      '--machine',
      '-d',
      device,
    ], workingDirectory: app);
    final wsUri = Completer<String>();
    final started = Completer<void>();
    String? appId;
    flutter.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!line.startsWith('[{')) return;
          for (final e in (jsonDecode(line) as List).cast<Map>()) {
            final params = e['params'] as Map?;
            if (e['event'] == 'app.debugPort' && !wsUri.isCompleted) {
              wsUri.complete(params!['wsUri'] as String);
              appId = params['appId'] as String?;
            }
            if (e['event'] == 'app.started' && !started.isCompleted) {
              started.complete();
            }
          }
        });
    flutter.stderr.transform(utf8.decoder).listen(stderr.write);
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
    server.stderr.transform(utf8.decoder).listen((_) {});
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
    }

    /// Like [check], but passes only if the text contains none of [absent].
    Future<void> checkAbsent(
      String label,
      String tool,
      Map<String, dynamic> a,
      List<String> absent,
    ) async {
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
        '${ok ? '✅' : '❌'} $label (${text.length}b)${ok ? '' : '\n   $text'}',
      );
    }

    /// Polls get_app_summary until its "Viewport: WxH" has the orientation.
    Future<void> expectViewport(String label, {required bool landscape}) async {
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
    }

    if (zeroCode) {
      // The SDK check runs up to 5 s after connecting; then the list shrinks.
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      Set<String> listed;
      do {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        listed =
            ((await mcp.request('tools/list', {}))['result']['tools'] as List)
                .map((t) => t['name'] as String)
                .toSet();
      } while (listed.length != zeroCodeTools.length &&
          DateTime.now().isBefore(deadline));
      final listOk =
          listed.length == zeroCodeTools.length &&
          listed.containsAll(zeroCodeTools);
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

      // Platform-specific tools are listed only where they can work.
      final listed =
          ((await mcp.request('tools/list', {}))['result']['tools'] as List)
              .map((t) => t['name'] as String)
              .toSet();
      final isIos = isMobile && !device.startsWith('emulator');
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
      await check('tap Send', 'tap_widget', {'key': 'Send'});
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
      // Errors (ROADMAP §3.10): a layout overflow is a bug to fix, not a
      // crash; an uncaught exception is flagged, with a small report that
      // points at the source line.
      await check('overflow the layout', 'tap_widget', {'key': 'Squeeze'});
      await check(
        'overflow is listed with its widget and line',
        'get_errors',
        {},
        ['overflowed', 'Row (lib/main.dart:'],
        false,
        react,
      );
      await checkAbsent(
        'an overflow is not an uncaught exception',
        'get_errors',
        {},
        ['since the last hot reload'],
      );
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
    server?.kill();
    flutter?.kill();
    work.deleteSync(recursive: true);
  }
  print(failed == 0 ? '\nE2E passed' : '\nE2E: $failed failed');
  exit(failed == 0 ? 0 : 1);
}

/// Minimal line-delimited JSON-RPC client for the MCP stdio transport.
class _Mcp {
  _Mcp(this._p) {
    _p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      try {
        final msg = jsonDecode(line) as Map<String, dynamic>;
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
    return c.future.timeout(
      const Duration(minutes: 3),
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
  WidgetsFlutterBinding.ensureInitialized();
  FlutterPilot.initialize();
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
  String _zoomed = 'zoom 1.0';
  bool _squeeze = false;
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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(children: [
      const Text('Version A'),
      // What set_app_settings(textScale/locale) reached, with no wiring above.
      Text('Scale ${MediaQuery.textScalerOf(context).scale(10) / 10}'),
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
      Row(children: [
        TextButton(
          onPressed: () => throw StateError('Boom from the Crash button'),
          child: const Text('Crash'),
        ),
        TextButton(
          onPressed: () => setState(() => _squeeze = !_squeeze),
          child: const Text('Squeeze'),
        ),
        Text('Key: $_lastKey x${_keyDowns[_lastKey] ?? 0}'),
        if (_squeeze)
          const SizedBox(width: 40, child: Row(children: [SizedBox(width: 90, height: 8)])),
      ]),
    ]),
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
