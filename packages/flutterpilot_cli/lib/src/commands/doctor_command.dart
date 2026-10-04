import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:yaml/yaml.dart';

import '../dtd_discovery.dart';
import 'init_command.dart';
import 'mcp_command.dart';

/// One finding: [ok] false with a [fix] is a problem; [warn] is advice.
class DoctorCheck {
  const DoctorCheck.ok(this.title) : ok = true, warn = false, fix = null;
  const DoctorCheck.warn(this.title, this.fix) : ok = true, warn = true;
  const DoctorCheck.fail(this.title, this.fix) : ok = false, warn = false;

  final String title;
  final bool ok;
  final bool warn;
  final String? fix;

  @override
  String toString() =>
      '${ok ? (warn ? '⚠️ ' : '✅') : '❌'} $title'
      '${fix == null ? '' : '\n     → $fix'}';
}

/// The service extension each plugin registers once it is wired.
const pluginExtensions = {
  'flutterpilot_bloc': 'ext.flutterpilot.getBlocStates',
  'flutterpilot_connectivity': 'ext.flutterpilot.getConnectivity',
  'flutterpilot_dio': 'ext.flutterpilot.getNetworkLogs',
  'flutterpilot_drift': 'ext.flutterpilot.queryDrift',
  'flutterpilot_firebase': 'ext.flutterpilot.getFirebaseAuth',
  'flutterpilot_gorouter': 'ext.flutterpilot.getGoRouterConfig',
  'flutterpilot_hive': 'ext.flutterpilot.getHiveContents',
  'flutterpilot_riverpod': 'ext.flutterpilot.getRiverpodStates',
  'flutterpilot_secure_storage': 'ext.flutterpilot.getSecureStorageKeys',
  'flutterpilot_shared_preferences': 'ext.flutterpilot.getSharedPreferences',
  'flutterpilot_sqflite': 'ext.flutterpilot.querySqflite',
  'flutterpilot_supabase': 'ext.flutterpilot.getSupabaseAuth',
};

/// Packages whose apps make HTTP requests (macOS needs network.client).
const _networkPackages = {
  'dio',
  'http',
  'supabase_flutter',
  'supabase',
  'graphql_flutter',
  'chopper',
  'retrofit',
  'web_socket_channel',
  'cached_network_image',
  'grpc',
};

/// `flutterpilot doctor`: checks that an app is set up for FlutterPilot and
/// that the running app answers, and prints the exact fix for each problem.
class DoctorCommand extends Command<void> {
  @override
  final String name = 'doctor';

  @override
  final String description =
      'Checks this app\'s FlutterPilot setup (SDK and plugin wiring, macOS '
      'entitlements, MCP client config) and, if it is running, that the SDK '
      'and plugins registered. Prints the exact fix for each problem.';

  DoctorCommand() {
    argParser.addOption(
      'project-root',
      abbr: 'p',
      help: 'Path to the Flutter project root (where pubspec.yaml lives).',
      defaultsTo: '.',
    );
  }

  @override
  Future<void> run() async {
    final project = p.normalize(
      p.absolute(argResults!['project-root'] as String),
    );
    stdout.writeln('FlutterPilot doctor — $project\n');
    final checks = [
      ...checkProject(project),
      ...await checkRunningApp(project),
    ];
    for (final c in checks) {
      stdout.writeln(c);
    }
    final problems = checks.where((c) => !c.ok).length;
    stdout.writeln(
      problems == 0
          ? '\nNo problems found.'
          : '\n$problems problem${problems == 1 ? '' : 's'} found.',
    );
    if (problems > 0) exitCode = 1;
  }

  /// What can be checked from the files alone.
  static List<DoctorCheck> checkProject(String project) {
    final pubspecFile = File(p.join(project, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return [
        const DoctorCheck.fail(
          'No pubspec.yaml here',
          'run doctor in your Flutter app (or pass -p <app folder>)',
        ),
      ];
    }
    final checks = <DoctorCheck>[];
    final pubspec = loadYaml(pubspecFile.readAsStringSync());
    final deps = <String>{
      for (final section in ['dependencies', 'dev_dependencies'])
        if (pubspec is Map && pubspec[section] is Map)
          ...(pubspec[section] as Map).keys.cast<String>(),
    };
    final source = appSources(project);

    // SDK
    if (!deps.contains('flutterpilot_sdk')) {
      checks.add(
        const DoctorCheck.warn(
          'flutterpilot_sdk is not a dependency: zero-code mode (inspect '
              'only; no taps, text entry or assertions)',
          'flutterpilot init',
        ),
      );
    } else if (!source.contains('FlutterPilot.initialize(')) {
      checks.add(
        const DoctorCheck.fail(
          'flutterpilot_sdk is added but FlutterPilot.initialize() is never '
              'called: the app runs without it',
          'first in main(): FlutterPilot.initialize(); (or run '
              'flutterpilot init)',
        ),
      );
    } else {
      checks.add(const DoctorCheck.ok('SDK added and initialized'));
    }

    // Plugins
    final wanted = <String, String>{
      for (final e in appPlugins.entries)
        if (deps.contains(e.key)) e.value.$1: e.value.$2,
    };
    for (final MapEntry(key: plugin, value: wiring) in wanted.entries) {
      if (!deps.contains(plugin)) {
        checks.add(
          DoctorCheck.warn(
            '$plugin is not added: its tools are not listed for this app',
            'flutterpilot init (adds it), then: $wiring',
          ),
        );
        continue;
      }
      final symbol = wiringSymbol(wiring);
      if (symbol != null && !source.contains(symbol)) {
        checks.add(
          DoctorCheck.fail(
            '$plugin is added but not wired ($symbol is never used): its '
            'tools stay hidden',
            wiring,
          ),
        );
      } else {
        checks.add(DoctorCheck.ok('$plugin added and wired'));
      }
    }

    // macOS sandbox: without network.client every HTTP request fails.
    if (Directory(p.join(project, 'macos')).existsSync()) {
      final missing = [
        for (final f in ['DebugProfile', 'Release'])
          if (!_entitled(project, f, 'com.apple.security.network.client'))
            'macos/Runner/$f.entitlements',
      ];
      final networked =
          deps.any(_networkPackages.contains) ||
          deps.any((d) => d.startsWith('firebase_') || d.startsWith('cloud_'));
      final title =
          'macOS: no com.apple.security.network.client in '
          '${missing.join(' and ')}: HTTP fails with errno = 1';
      final fix =
          'add <key>com.apple.security.network.client</key><true/> to '
          '${missing.join(' and ')}';
      checks.add(
        missing.isEmpty
            ? const DoctorCheck.ok('macOS: network.client entitlement')
            : networked
            ? DoctorCheck.fail(title, fix)
            : DoctorCheck.warn('$title (if the app makes requests)', fix),
      );
    }

    // MCP client
    checks.add(checkMcpConfig(project));
    return checks;
  }

  /// Whether some client's config has FlutterPilot, and its server exists.
  static DoctorCheck checkMcpConfig(String project) {
    final configured = <String>[];
    for (final client in McpClient.values) {
      final file = File(p.join(project, client.configPath));
      if (!file.existsSync()) continue;
      final ServerLaunch? launch;
      try {
        launch = McpInstallCommand.installedLaunch(project, client);
      } catch (_) {
        // JSONC: can't read it, but it mentions us.
        if (file.readAsStringSync().contains('"flutterpilot"')) {
          configured.add(client.label);
        }
        continue;
      }
      if (launch == null) continue;
      // `dart run <script>` or a compiled server: the file must exist.
      final server = p.basename(launch.command).startsWith('dart')
          ? launch.args.firstWhere((a) => a.endsWith('.dart'), orElse: () => '')
          : launch.command;
      if (server.isNotEmpty &&
          p.isAbsolute(server) &&
          !File(server).existsSync()) {
        return DoctorCheck.fail(
          '${client.label}: ${client.configPath} starts $server, which does '
              'not exist',
          'flutterpilot mcp install',
        );
      }
      configured.add(client.label);
    }
    return configured.isEmpty
        ? const DoctorCheck.warn(
            'No MCP client in this project is set up for FlutterPilot',
            'flutterpilot mcp install',
          )
        : DoctorCheck.ok('MCP config: ${configured.join(', ')}');
  }

  /// Connects to the running app — from its URI file (`flutterpilot dev`),
  /// else from the Dart Tooling Daemon a plain `flutter run` or an IDE
  /// registers it with — and checks what registered.
  static Future<List<DoctorCheck>> checkRunningApp(
    String project, {
    Future<List<DtdApp>> Function()? dtdApps,
  }) async {
    final file = File(p.join(project, '.dart_tool', 'flutterpilot_vm_uri'));
    const start = 'flutter run, flutterpilot dev or your IDE';
    final fromDtd =
        (await (dtdApps ?? DtdDiscovery.apps)())
            .where((a) => a.isUnder([Directory(project)], maxDepth: 0))
            .toList()
          ..sort((a, b) => b.started.compareTo(a.started));
    final uris = [
      if (file.existsSync()) _wsUri(file.readAsStringSync().trim()),
      for (final app in fromDtd) app.uri,
    ];
    for (final uri in uris) {
      VmService? vm;
      try {
        vm = await vmServiceConnectUri(uri).timeout(const Duration(seconds: 3));
        final extensions = <String>{};
        for (final ref in (await vm.getVM()).isolates ?? const <IsolateRef>[]) {
          final isolate = await vm.getIsolate(ref.id!);
          extensions.addAll(isolate.extensionRPCs ?? const []);
        }
        return checkExtensions(project, extensions);
      } catch (_) {
        // Stopped: try the next.
      } finally {
        await vm?.dispose();
      }
    }
    return [
      DoctorCheck.warn(
        file.existsSync()
            ? 'App not running: .dart_tool/flutterpilot_vm_uri names an app '
                  'that stopped; runtime checks skipped'
            : 'App not running: runtime checks skipped',
        start,
      ),
    ];
  }

  /// Runtime checks from the running app's registered [extensions].
  static List<DoctorCheck> checkExtensions(
    String project,
    Set<String> extensions,
  ) {
    final deps = _dependencies(project);
    if (!deps.contains('flutterpilot_sdk')) {
      return [const DoctorCheck.ok('App running (zero-code: inspect only)')];
    }
    final checks = <DoctorCheck>[const DoctorCheck.ok('App running')];
    if (!extensions.any((e) => e.startsWith('ext.flutterpilot.'))) {
      checks.add(
        const DoctorCheck.fail(
          'The running app has no FlutterPilot extensions: the SDK is not '
              'initialized in this build',
          'call FlutterPilot.initialize() in main(), then hot restart',
        ),
      );
      return checks;
    }
    checks.add(const DoctorCheck.ok('SDK registered in the running app'));
    for (final MapEntry(key: plugin, value: extension)
        in pluginExtensions.entries) {
      if (!deps.contains(plugin)) continue;
      final wiring = appPlugins.values
          .firstWhere((v) => v.$1 == plugin, orElse: () => (plugin, ''))
          .$2;
      checks.add(
        extensions.contains(extension)
            ? DoctorCheck.ok('$plugin registered')
            : DoctorCheck.fail(
                '$plugin has not registered in the running app: its tools '
                    'are not listed',
                '${wiring.isEmpty ? 'wire it' : wiring} — at startup, '
                    'then hot restart',
              ),
      );
    }
    return checks;
  }

  static Set<String> _dependencies(String project) {
    try {
      final pubspec = loadYaml(
        File(p.join(project, 'pubspec.yaml')).readAsStringSync(),
      );
      return {
        for (final section in ['dependencies', 'dev_dependencies'])
          if (pubspec is Map && pubspec[section] is Map)
            ...(pubspec[section] as Map).keys.cast<String>(),
      };
    } catch (_) {
      return {};
    }
  }

  static bool _entitled(String project, String file, String key) {
    final f = File(p.join(project, 'macos', 'Runner', '$file.entitlements'));
    if (!f.existsSync()) return false;
    return RegExp(
      '<key>${RegExp.escape(key)}</key>\\s*<true\\s*/>',
    ).hasMatch(f.readAsStringSync());
  }

  /// flutter run writes `ws://…/ws`; accept the `http://…/` form too.
  static String _wsUri(String raw) {
    final uri = Uri.parse(raw);
    if (uri.scheme.startsWith('ws')) return raw;
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri
        .replace(
          scheme: uri.scheme == 'https' ? 'wss' : 'ws',
          path: '${path}ws',
        )
        .toString();
  }
}
