import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:yaml/yaml.dart';

import '../devices_check.dart';
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
  'fp_bloc': 'ext.flutterpilot.getBlocStates',
  'fp_connectivity': 'ext.flutterpilot.getConnectivity',
  'fp_dio': 'ext.flutterpilot.getNetworkLogs',
  'fp_drift': 'ext.flutterpilot.queryDrift',
  'fp_firebase': 'ext.flutterpilot.getFirebaseAuth',
  'fp_gorouter': 'ext.flutterpilot.getGoRouterConfig',
  'fp_hive': 'ext.flutterpilot.getHiveContents',
  'fp_riverpod': 'ext.flutterpilot.getRiverpodStates',
  'fp_secure_storage': 'ext.flutterpilot.getSecureStorageKeys',
  'fp_shared_preferences': 'ext.flutterpilot.getSharedPreferences',
  'fp_sqflite': 'ext.flutterpilot.querySqflite',
  'fp_supabase': 'ext.flutterpilot.getSupabaseAuth',
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
      ...await checkDevices(),
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
    final hasSdk = deps.contains('fp_sdk') || deps.contains('flutterpilot_sdk');
    if (!hasSdk) {
      checks.add(
        const DoctorCheck.warn(
          'fp_sdk is not a dependency: zero-code mode (inspect '
              'only; no taps, text entry or assertions)',
          'flutterpilot init',
        ),
      );
    } else if (!source.contains('FlutterPilot.initialize(')) {
      checks.add(
        const DoctorCheck.fail(
          'fp_sdk is added but FlutterPilot.initialize() is never '
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
      final legacyPlugin = plugin.replaceFirst('fp_', 'flutterpilot_');
      final hasPlugin = deps.contains(plugin) || deps.contains(legacyPlugin);
      if (!hasPlugin) {
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

      final sandboxCheck = _checkMacOsSandbox(project);
      if (sandboxCheck != null) checks.add(sandboxCheck);
    }

    // MCP client
    checks.add(checkMcpConfig(project));
    return checks;
  }

  /// Says when a compiled server in a source checkout
  /// (`…/fp_server/build/fp_server`) was built before its
  /// source last changed: agents then run old tools while the repo, the docs
  /// and the app's SDK have moved on. Null when it is current or not such a
  /// binary.
  static String? staleServerBinary(String server) {
    final binary = File(server);
    final package = Directory(p.dirname(p.dirname(server)));
    if (p.basename(p.dirname(server)) != 'build' ||
        !binary.existsSync() ||
        !File(p.join(package.path, 'pubspec.yaml')).existsSync()) {
      return null;
    }
    final built = binary.lastModifiedSync();
    var newer = 0;
    for (final dir in ['lib', 'bin']) {
      final source = Directory(p.join(package.path, dir));
      if (!source.existsSync()) continue;
      for (final file in source.listSync(recursive: true)) {
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.lastModifiedSync().isAfter(built)) {
          newer++;
        }
      }
    }
    return newer == 0
        ? null
        : 'the server binary $server was compiled before $newer of its '
              'source files last changed';
  }

  /// Whether [command] is found in one of the PATH's folders ([path]
  /// defaults to the environment's).
  static bool onPath(String command, {String? path}) {
    final dirs = (path ?? Platform.environment['PATH'] ?? '').split(
      Platform.isWindows ? ';' : ':',
    );
    final names = Platform.isWindows
        ? [command, '$command.exe', '$command.bat', '$command.cmd']
        : [command];
    for (final dir in dirs) {
      if (dir.isEmpty) continue;
      for (final name in names) {
        if (File(p.join(dir, name)).existsSync()) return true;
      }
    }
    return false;
  }

  /// The FlutterPilot server commands Claude Code has for [project] outside
  /// it: the project's entry and the user-level one in `~/.claude.json`.
  static List<String> claudeLocalServers(String project, {String? home}) {
    final dir =
        home ??
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (dir == null) return const [];
    try {
      final json = jsonDecode(
        File(p.join(dir, '.claude.json')).readAsStringSync(),
      );
      if (json is! Map) return const [];
      String? command(Object? servers) {
        final entry = servers is Map ? servers['flutterpilot'] : null;
        final command = entry is Map ? entry['command'] : null;
        return command is String ? command : null;
      }

      final projects = json['projects'];
      final forProject = projects is Map
          ? projects[p.normalize(p.absolute(project))]
          : null;
      return {
        ?command(forProject is Map ? forProject['mcpServers'] : null),
        ?command(json['mcpServers']),
      }.toList();
    } catch (_) {
      return const [];
    }
  }

  /// Whether some client's config has FlutterPilot, and its server exists.
  static DoctorCheck checkMcpConfig(
    String project, {
    String? home,
    String? path,
  }) {
    final configured = <String>[];
    DoctorCheck? warning;
    // Claude Code also keeps servers outside the project (added with
    // "claude mcp add"): per project and for the user, in ~/.claude.json.
    // They win over the project's .mcp.json, so they are what runs.
    for (final command in claudeLocalServers(project, home: home)) {
      if (p.isAbsolute(command) && !File(command).existsSync()) {
        return DoctorCheck.fail(
          'Claude Code (~/.claude.json) starts $command, which does not exist',
          'flutterpilot mcp install',
        );
      }
      if (staleServerBinary(command) case final stale?) {
        // Not returned yet: a config that cannot start at all comes first.
        warning ??= DoctorCheck.warn(
          'Claude Code (~/.claude.json): $stale',
          'recompile it (dart compile exe bin/fp_server.dart -o '
              'build/fp_server in that package), then restart '
              'Claude Code',
        );
        continue;
      }
      configured.add('Claude Code (~/.claude.json)');
    }
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
      // A config kept free of machine paths names the server alone
      // ("fp_server"): that only works where it is on the PATH.
      if (!p.isAbsolute(launch.command) &&
          !launch.command.contains(p.separator) &&
          !onPath(launch.command, path: path)) {
        return DoctorCheck.fail(
          '${client.label}: ${client.configPath} starts '
              '"${launch.command}", which is not on the PATH',
          'put it there (e.g. ln -s <FlutterPilot>/packages/'
              'fp_server/build/fp_server '
              '~/.local/bin/${launch.command}), or flutterpilot mcp install '
              'for a config with this machine\'s path',
        );
      }
      if (server.isNotEmpty &&
          p.isAbsolute(server) &&
          !File(server).existsSync()) {
        return DoctorCheck.fail(
          '${client.label}: ${client.configPath} starts $server, which does '
              'not exist',
          'flutterpilot mcp install',
        );
      }
      if (staleServerBinary(server) case final stale?) {
        warning ??= DoctorCheck.warn(
          '${client.label}: $stale',
          'flutterpilot mcp install  (recompiles it), then restart the MCP '
              'client',
        );
        continue;
      }
      final toolsAt = launch.args.indexOf('--tools');
      final profile =
          toolsAt >= 0 &&
              toolsAt + 1 < launch.args.length &&
              launch.args[toolsAt + 1] == 'core'
          ? ' (core tools)'
          : '';
      configured.add('${client.label}$profile');
    }
    if (warning != null) return warning;
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
    if (!deps.contains('fp_sdk') && !deps.contains('flutterpilot_sdk')) {
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
      final legacyPlugin = plugin.replaceFirst('fp_', 'flutterpilot_');
      if (!deps.contains(plugin) && !deps.contains(legacyPlugin)) continue;
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

  static DoctorCheck? _checkMacOsSandbox(String project) {
    if (!Directory(p.join(project, 'macos')).existsSync()) return null;

    final isDebugSandboxed = _entitled(
      project,
      'DebugProfile',
      'com.apple.security.app-sandbox',
    );
    if (!isDebugSandboxed) {
      return const DoctorCheck.ok(
        'macOS: DebugProfile app-sandbox disabled (unrestricted hot reload)',
      );
    }

    final appInfo = File(
      p.join(project, 'macos', 'Runner', 'Configs', 'AppInfo.xcconfig'),
    );
    String? bundleId;
    if (appInfo.existsSync()) {
      final match = RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([a-zA-Z0-9_.-]+)',
      ).firstMatch(appInfo.readAsStringSync());
      if (match != null) bundleId = match.group(1);
    }

    if (bundleId != null && Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final containerTmp = Directory(
          p.join(home, 'Library', 'Containers', bundleId, 'Data', 'tmp'),
        );
        if (containerTmp.existsSync()) {
          final probe = File(p.join(containerTmp.path, '.fp_write_probe'));
          try {
            probe.writeAsStringSync('ok');
            probe.deleteSync();
            return DoctorCheck.ok(
              'macOS: sandboxed container write access verified ($bundleId)',
            );
          } catch (e) {
            return DoctorCheck.fail(
              'macOS: blocked from writing to app container ($bundleId): $e',
              'Grant terminal App Management permission under System Settings > '
              'Privacy & Security > App Management, or set '
              '<key>com.apple.security.app-sandbox</key><false/> in macos/Runner/DebugProfile.entitlements',
            );
          }
        }
      }
    }

    return const DoctorCheck.ok(
      'macOS: app-sandbox entitlement configured for DebugProfile',
    );
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
