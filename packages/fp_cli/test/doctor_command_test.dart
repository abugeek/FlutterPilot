import 'dart:convert';
import 'dart:io';
import 'package:fp_cli/fp_cli.dart';
import 'package:fp_cli/src/dtd_discovery.dart';
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
    pubspec(['flutter', 'fp_sdk']);
    write('lib/main.dart', 'void main() {}');
    final checks = DoctorCommand.checkProject(app.path);
    expect(titles(checks, ok: false).single, contains('never called'));
  });

  // Field case: an app wires FlutterPilot in a dev-only entrypoint
  // (flutter run -t tool/pilot_main.dart) so lib/ never imports it, and
  // doctor reported seven things as missing that the running app had.
  test('wiring in a tool/ entrypoint counts', () {
    pubspec(['flutter', 'fp_sdk', 'dio', 'fp_dio']);
    write('lib/main.dart', 'void main() {}');
    write(
      'tool/pilot_main.dart',
      'void main() { FlutterPilot.initialize(); DioPilotInterceptor.register(); }',
    );
    final checks = DoctorCommand.checkProject(app.path);
    expect(titles(checks, ok: false), isEmpty);
  });

  test('a plugin added but not wired, and one missing', () {
    pubspec(['fp_sdk', 'dio', 'fp_dio', 'hive']);
    write('lib/main.dart', 'void main() { FlutterPilot.initialize(); }');
    final checks = DoctorCommand.checkProject(app.path);
    final dio = checks.firstWhere((c) => c.title.contains('fp_dio'));
    expect(dio.ok, isFalse);
    expect(dio.fix, contains('DioPilotInterceptor'));
    final hive = checks.firstWhere((c) => c.title.contains('fp_hive'));
    expect(hive.warn, isTrue);
    expect(hive.fix, contains('flutterpilot init'));
  });

  test('a wired plugin passes', () {
    pubspec(['fp_sdk', 'dio', 'fp_dio']);
    write(
      'lib/main.dart',
      'void main() { FlutterPilot.initialize(); DioPilotInterceptor.register(); }',
    );
    expect(
      titles(DoctorCommand.checkProject(app.path), ok: true),
      containsAll(['SDK added and initialized', 'fp_dio added and wired']),
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

  // Field case: agents ran a server compiled days before its source moved.
  test('a compiled server older than its source is pointed out', () {
    final package = Directory(p.join(app.path, 'fp_server'));
    File(p.join(package.path, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: fp_server');
    final source = File(p.join(package.path, 'lib', 'server.dart'))
      ..createSync(recursive: true);
    final binary = File(p.join(package.path, 'build', 'fp_server'))
      ..createSync(recursive: true);
    final built = DateTime(2026, 10, 5);
    binary.setLastModifiedSync(built);
    source.setLastModifiedSync(built.subtract(const Duration(days: 1)));
    expect(DoctorCommand.staleServerBinary(binary.path), isNull);
    source.setLastModifiedSync(built.add(const Duration(days: 6)));
    expect(
      DoctorCommand.staleServerBinary(binary.path),
      contains('compiled before 1 of its source files last changed'),
    );
    // A server installed elsewhere (pub cache, a release) is not judged.
    expect(DoctorCommand.staleServerBinary('/usr/local/bin/server'), isNull);
  });

  // Field case: a config kept free of machine paths ("fp_server")
  // on a machine where nothing by that name was installed; doctor said ✅.
  test('a server named without a path must be on the PATH', () {
    pubspec([]);
    write(
      '.mcp.json',
      jsonEncode({
        'mcpServers': {
          'flutterpilot': {
            'command': 'fp_server',
            'args': ['-p', '.'],
          },
        },
      }),
    );
    final bin = Directory(p.join(app.path, 'bin'))..createSync();
    final missing = DoctorCommand.checkMcpConfig(
      app.path,
      home: app.path,
      path: bin.path,
    );
    expect(missing.ok, isFalse);
    expect(missing.title, contains('"fp_server", which is not on'));
    File(p.join(bin.path, 'fp_server')).createSync();
    expect(
      DoctorCommand.checkMcpConfig(app.path, home: app.path, path: bin.path).ok,
      isTrue,
    );
  });

  test("Claude Code's own config outside the project is checked too", () {
    pubspec([]);
    final home = Directory(p.join(app.path, 'home'))..createSync();
    final package = Directory(p.join(app.path, 'fp_server'));
    File(p.join(package.path, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: fp_server');
    final source = File(p.join(package.path, 'lib', 'server.dart'))
      ..createSync(recursive: true);
    final binary = File(p.join(package.path, 'build', 'fp_server'))
      ..createSync(recursive: true);
    binary.setLastModifiedSync(DateTime(2026, 10, 5));
    source.setLastModifiedSync(DateTime(2026, 10, 11));
    File(p.join(home.path, '.claude.json')).writeAsStringSync(
      jsonEncode({
        'projects': {
          p.normalize(p.absolute(app.path)): {
            'mcpServers': {
              'flutterpilot': {'command': binary.path, 'args': []},
            },
          },
        },
      }),
    );
    final check = DoctorCommand.checkMcpConfig(app.path, home: home.path);
    expect(check.warn, isTrue);
    expect(check.title, contains('Claude Code (~/.claude.json)'));
    expect(check.title, contains('compiled before 1 of its source files'));

    source.setLastModifiedSync(DateTime(2026, 10, 1));
    final fine = DoctorCommand.checkMcpConfig(app.path, home: home.path);
    expect(fine.warn, isFalse);
    expect(fine.title, contains('Claude Code (~/.claude.json)'));
  });

  test('MCP config: missing, pointing at a missing server, fine', () {
    pubspec([]);
    expect(
      DoctorCommand.checkMcpConfig(app.path, home: app.path).fix,
      'flutterpilot mcp install',
    );
    write(
      '.mcp.json',
      jsonEncode({
        'mcpServers': {
          'flutterpilot': {'command': '/nope/fp_server', 'args': []},
        },
      }),
    );
    final missing = DoctorCommand.checkMcpConfig(app.path, home: app.path);
    expect(missing.ok, isFalse);
    expect(missing.title, contains('/nope/fp_server'));
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
    expect(DoctorCommand.checkMcpConfig(app.path, home: app.path).ok, isTrue);
    // Codex's TOML and opencode's command list are read too.
    File(p.join(app.path, '.mcp.json')).deleteSync();
    write(
      '.codex/config.toml',
      '[mcp_servers.flutterpilot]\ncommand = "/nope/server"\nargs = []\n',
    );
    expect(
      DoctorCommand.checkMcpConfig(app.path, home: app.path).title,
      contains('Codex: .codex/config.toml starts /nope/server'),
    );
    File(p.join(app.path, '.codex', 'config.toml')).deleteSync();
    write(
      'opencode.json',
      jsonEncode({
        'mcp': {
          'flutterpilot': {
            'type': 'local',
            'command': [Platform.resolvedExecutable, 'run', 'x'],
          },
        },
      }),
    );
    expect(
      DoctorCommand.checkMcpConfig(app.path, home: app.path).title,
      'MCP config: opencode',
    );
  });

  test('MCP config: the tool profile a client uses is shown', () {
    pubspec([]);
    write(
      '.mcp.json',
      jsonEncode({
        'mcpServers': {
          'flutterpilot': {
            'command': Platform.resolvedExecutable,
            'args': [
              'run',
              p.join(app.path, 'pubspec.yaml'),
              '--tools',
              'core',
              '-p',
              app.path,
            ],
          },
        },
      }),
    );
    expect(
      DoctorCommand.checkMcpConfig(app.path, home: app.path).title,
      'MCP config: Claude Code (core tools)',
    );
  });

  test('runtime: SDK and each plugin must have registered', () {
    pubspec(['dio']);
    expect(
      DoctorCommand.checkExtensions(app.path, {}).single.title,
      contains('zero-code'),
    );
    pubspec(['fp_sdk', 'dio', 'fp_dio', 'fp_hive']);
    var checks = DoctorCommand.checkExtensions(app.path, {'ext.flutter.x'});
    expect(titles(checks, ok: false).single, contains('no FlutterPilot'));
    checks = DoctorCommand.checkExtensions(app.path, {
      'ext.flutterpilot.getAppSummary',
      'ext.flutterpilot.getNetworkLogs',
    });
    expect(titles(checks, ok: true), contains('fp_dio registered'));
    final hive = checks.firstWhere((c) => c.title.contains('fp_hive'));
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
