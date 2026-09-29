import 'dart:convert';
import 'dart:io';
import 'package:flutterpilot_cli/flutterpilot_cli.dart';
import 'package:flutterpilot_cli/src/dtd_discovery.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory app;

  setUp(() => app = Directory.systemTemp.createTempSync('fp_doctor_'));
  tearDown(() => app.deleteSync(recursive: true));

  void write(String path, String content) => File(p.join(app.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  void pubspec(List<String> deps) => write(
    'pubspec.yaml',
    'name: app\ndependencies:\n'
        '${deps.map((d) => '  $d: any\n').join()}',
  );

  List<String> titles(List<DoctorCheck> checks, {required bool ok}) => [
    for (final c in checks)
      if (c.ok == ok && !c.warn) c.title,
  ];

  test('no pubspec: one failure saying where to run it', () {
    final checks = DoctorCommand.checkProject(app.path);
    expect(checks.single.ok, isFalse);
    expect(checks.single.fix, contains('-p'));
  });

  test('SDK added but never initialized', () {
    pubspec(['flutter', 'flutterpilot_sdk']);
    write('lib/main.dart', 'void main() {}');
    final checks = DoctorCommand.checkProject(app.path);
    expect(titles(checks, ok: false).single, contains('never called'));
  });

  test('a plugin added but not wired, and one missing', () {
    pubspec(['flutterpilot_sdk', 'dio', 'flutterpilot_dio', 'hive']);
    write('lib/main.dart', 'void main() { FlutterPilot.initialize(); }');
    final checks = DoctorCommand.checkProject(app.path);
    final dio = checks.firstWhere((c) => c.title.contains('flutterpilot_dio'));
    expect(dio.ok, isFalse);
    expect(dio.fix, contains('DioPilotInterceptor'));
    final hive = checks.firstWhere(
      (c) => c.title.contains('flutterpilot_hive'),
    );
    expect(hive.warn, isTrue);
    expect(hive.fix, contains('flutterpilot init'));
  });

  test('a wired plugin passes', () {
    pubspec(['flutterpilot_sdk', 'dio', 'flutterpilot_dio']);
    write(
      'lib/main.dart',
      'void main() { FlutterPilot.initialize(); DioPilotInterceptor.register(); }',
    );
    expect(
      titles(DoctorCommand.checkProject(app.path), ok: true),
      containsAll([
        'SDK added and initialized',
        'flutterpilot_dio added and wired',
      ]),
    );
  });

  test('macOS network.client: an error for networked apps only', () {
    write('macos/Runner/DebugProfile.entitlements', '<dict></dict>');
    write(
      'macos/Runner/Release.entitlements',
      '<key>com.apple.security.network.client</key>\n<true/>',
    );
    pubspec(['hive']);
    var mac = DoctorCommand.checkProject(
      app.path,
    ).firstWhere((c) => c.title.startsWith('macOS'));
    expect(mac.warn, isTrue);
    expect(mac.title, contains('DebugProfile'));
    expect(mac.title, isNot(contains('Release')));
    pubspec(['http']);
    mac = DoctorCommand.checkProject(
      app.path,
    ).firstWhere((c) => c.title.startsWith('macOS'));
    expect(mac.ok, isFalse);
  });

  test('MCP config: missing, pointing at a missing server, fine', () {
    pubspec([]);
    expect(
      DoctorCommand.checkMcpConfig(app.path).fix,
      'flutterpilot mcp install',
    );
    write(
      '.mcp.json',
      jsonEncode({
        'mcpServers': {
          'flutterpilot': {'command': '/nope/flutterpilot_server', 'args': []},
        },
      }),
    );
    final missing = DoctorCommand.checkMcpConfig(app.path);
    expect(missing.ok, isFalse);
    expect(missing.title, contains('/nope/flutterpilot_server'));
    write(
      '.mcp.json',
      jsonEncode({
        'mcpServers': {
          'flutterpilot': {
            'command': Platform.resolvedExecutable,
            'args': ['run', p.join(app.path, 'pubspec.yaml')],
          },
        },
      }),
    );
    expect(DoctorCommand.checkMcpConfig(app.path).ok, isTrue);
  });

  test('runtime: SDK and each plugin must have registered', () {
    pubspec(['dio']);
    expect(
      DoctorCommand.checkExtensions(app.path, {}).single.title,
      contains('zero-code'),
    );
    pubspec([
      'flutterpilot_sdk',
      'dio',
      'flutterpilot_dio',
      'flutterpilot_hive',
    ]);
    var checks = DoctorCommand.checkExtensions(app.path, {'ext.flutter.x'});
    expect(titles(checks, ok: false).single, contains('no FlutterPilot'));
    checks = DoctorCommand.checkExtensions(app.path, {
      'ext.flutterpilot.getAppSummary',
      'ext.flutterpilot.getNetworkLogs',
    });
    expect(titles(checks, ok: true), contains('flutterpilot_dio registered'));
    final hive = checks.firstWhere(
      (c) => c.title.contains('flutterpilot_hive'),
    );
    expect(hive.ok, isFalse);
    expect(hive.fix, contains('HivePilotInspector.registerBox'));
  });

  test('runtime checks are skipped when the app is not running', () async {
    pubspec([]);
    // An app a plain `flutter run` registered with its tooling daemon
    // (here one that stopped) is tried too.
    var asked = 0;
    Future<List<DtdApp>> daemons() async {
      asked++;
      return [
        DtdApp(
          uri: 'ws://127.0.0.1:2/y=/ws',
          workspaceRoot: app.path,
          started: DateTime.now(),
        ),
      ];
    }

    final checks = await DoctorCommand.checkRunningApp(
      app.path,
      dtdApps: daemons,
    );
    expect(checks.single.warn, isTrue);
    expect(checks.single.fix, contains('flutter run'));
    write('.dart_tool/flutterpilot_vm_uri', 'ws://127.0.0.1:1/x=/ws');
    final stale = await DoctorCommand.checkRunningApp(
      app.path,
      dtdApps: daemons,
    );
    expect(stale.single.title, contains('stopped'));
    expect(asked, 2);
  });
}
