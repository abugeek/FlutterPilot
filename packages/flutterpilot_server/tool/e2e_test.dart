import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// End-to-end test of the real agent path:
///   fresh `flutter create` app -> `flutterpilot init --local` -> `flutter run`
///   -> MCP server over stdio -> tools/call.
///
/// Usage (from packages/flutterpilot_server):
///   dart run tool/e2e_test.dart [-d <device>]   # default device: macos
///
/// Covers: init wiring, widget tree, enter_text, press_key, secondary_tap,
/// pinch_zoom, interactive elements, covered-route assertions, tap_widget, Dio mock + network logs,
/// hot_reload applying an edited source file with state kept, hot_restart.
Future<void> main(List<String> args) async {
  final device = args.length == 2 && args[0] == '-d' ? args[1] : 'macos';
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
      '--platforms=macos,ios',
      'fixture',
    ], cwd: work.path);
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
    final uri = await wsUri.future.timeout(const Duration(minutes: 10));
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
      final shown = text.length > 300 ? '${text.substring(0, 300)}…' : text;
      print(
        '${ok ? '✅' : '❌'} $label (${text.length}b)${ok ? '' : '\n   $shown'}',
      );
    }

    const settle = Duration(seconds: 10);
    await check('app summary', 'get_app_summary', {}, [], false, settle, 4096);
    await check(
      'list_connected_devices shows auto-discovered default',
      'list_connected_devices',
      {},
      ['default'],
    );
    await check(
      'set_device_rotation honest on desktop',
      'set_device_rotation',
      {'orientation': 'landscape'},
      ['Not applicable on desktop', 'skipped'],
    );
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
    await check('enter text', 'enter_text', {
      'key': "TextField['Name']",
      'text': 'Pilot',
    });
    await check('tap Send', 'tap_widget', {'key': 'Send'});
    await check(
      'mocked response reached UI',
      'assert_text_visible',
      {'text': 'Hello, Pilot (200)'},
      [],
      false,
      const Duration(seconds: 5),
    );
    await check('network log has mocked call', 'get_network_logs', {}, [
      '/ping',
      '200',
    ]);

    // Keyboard, context menu, pinch, discovery, and on-screen-only assertions.
    // enter_text focuses the field (the tap on Send above moved focus away).
    await check('focus field again', 'enter_text', {
      'key': "TextField['Name']",
      'text': 'Pilot',
    });
    await check('press_key enter submits field', 'press_key', {'key': 'enter'});
    await check('submit handled', 'assert_text_visible', {
      'text': 'Submitted: Pilot',
    });
    await check('secondary_tap', 'secondary_tap', {'key': 'card'});
    await check('context handler ran', 'assert_text_visible', {
      'text': 'Context menu opened',
    });
    await check('pinch_zoom', 'pinch_zoom', {'key': 'zoomable', 'scale': 2.0});
    await check(
      'zoom applied',
      'assert_text_visible',
      {'text': 'zoom 1.0'},
      [],
      true,
    );
    await check('interactive elements', 'get_interactive_elements', {}, [
      'Send',
      'card',
    ]);
    // `target` works wherever `key` does.
    await check('target alias', 'assert_widget_visible', {'target': 'Send'});
    // Post-action state waits for the page transition: it lists the new
    // page's back button, not the previous screen.
    await check(
      'open details',
      'tap_widget',
      {'key': 'Details'},
      ['Route changed', 'Back'],
    );
    await check(
      'covered route is not "visible"',
      'assert_text_visible',
      {'text': 'Version A'},
      [],
      true,
      const Duration(seconds: 3), // after the page transition ends
    );
    await check('back', 'press_back');
    await check(
      'home visible again',
      'assert_text_visible',
      {'text': 'Version A'},
      [],
      false,
      const Duration(seconds: 3),
    );

    final main = File('$app/lib/main.dart');
    main.writeAsStringSync(
      main.readAsStringSync().replaceFirst('Version A', 'Version B'),
    );
    await check('hot_reload', 'hot_reload');
    await check(
      'reload applied edited source',
      'assert_text_visible',
      {'text': 'Version B'},
      [],
      false,
      const Duration(seconds: 5),
    );
    await check('reload kept state', 'assert_text_visible', {
      'text': 'Hello, Pilot (200)',
    });

    await check('hot_restart', 'hot_restart');
    await check(
      'app back after restart',
      'assert_text_visible',
      {'text': 'Version B'},
      [],
      false,
      settle,
    );
    await check(
      'restart reset state',
      'assert_text_visible',
      {'text': 'Hello, Pilot'},
      [],
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
import 'package:flutterpilot_dio/flutterpilot_dio.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

late final Dio dio;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterPilot.initialize();
  dio = Dio()..interceptors.add(DioPilotInterceptor());
  runApp(MaterialApp(navigatorObservers: [NavigationTracker()], home: const Home()));
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

  Future<void> _send() async {
    final res = await dio.get('https://example.com/ping');
    setState(() => _greeting = 'Hello, ${_name.text} (${res.statusCode})');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(children: [
      const Text('Version A'),
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
            builder: (_) => Scaffold(appBar: AppBar(title: const Text('Details page'))),
          ),
        ),
        child: const Text('Details'),
      ),
    ]),
  );
}
''';
