import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../smoke.dart';
import 'mcp_command.dart';

/// `flutterpilot smoke`: start the app (or use the running one), visit its
/// screens, check each for layout and accessibility problems and errors, and
/// write a report with a screenshot of every screen that has findings.
class SmokeCommand extends Command<void> {
  @override
  final String name = 'smoke';

  @override
  final String description =
      'Launch the app, visit its screens and write a health report '
      '(layout, accessibility, errors).';

  SmokeCommand() {
    argParser
      ..addOption(
        'project-root',
        abbr: 'p',
        help: 'The Flutter app folder.',
        defaultsTo: '.',
      )
      ..addOption('device', abbr: 'd', help: 'flutter run -d: a device id.')
      ..addOption(
        'routes',
        abbr: 'r',
        help:
            'Comma-separated routes to visit. Default: the current screen '
            'and, with go_router, every route without parameters.',
      )
      ..addOption(
        'out',
        help: 'Report folder. Default: flutterpilot/reports/smoke-<time>.',
      )
      ..addFlag(
        'launch',
        defaultsTo: true,
        help: 'Build and start the app (--no-launch: use the running one).',
      )
      ..addFlag(
        'relaunch',
        negatable: false,
        help:
            'Stop the running app and build it again (for --device, a '
            'changed pubspec or native code).',
      )
      ..addOption(
        'server',
        help:
            'The flutterpilot_server executable (default: the one beside '
            'this CLI, else \$FLUTTERPILOT_SERVER).',
      )
      ..addOption(
        'local',
        help: 'A FlutterPilot checkout to take the server from.',
      );
  }

  @override
  Future<void> run() async {
    final project = p.normalize(
      p.absolute(argResults!['project-root'] as String),
    );
    if (!File(p.join(project, 'pubspec.yaml')).existsSync()) {
      usageException('No pubspec.yaml in $project.');
    }
    final device = argResults!['device'] as String?;
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(':', '-');
    final out = Directory(
      argResults!['out'] as String? ??
          p.join(project, 'flutterpilot', 'reports', 'smoke-$stamp'),
    )..createSync(recursive: true);

    final server = await _serverCommand(project);
    stdout.writeln('FlutterPilot smoke — $project');
    final log = File(p.join(out.path, 'server.log')).openWrite();
    final session = await McpSession.start(
      server.executable,
      server.args,
      workingDirectory: server.workingDirectory,
      log: log,
    );
    try {
      final failed = await _smoke(session, project, device, out);
      exitCode = failed ? 1 : 0;
    } finally {
      await session.close();
      await log.close();
    }
  }

  Future<bool> _smoke(
    McpSession s,
    String project,
    String? device,
    Directory out,
  ) async {
    if (argResults!['launch'] as bool) {
      stdout.writeln('Launching the app (minutes the first time)…');
      final launch = await s.call('launch_app', {
        'device': ?device,
        if (argResults!['relaunch'] as bool) 'relaunch': true,
      }, timeout: const Duration(minutes: 15));
      final running = launch.text.startsWith('Already running and connected');
      if (launch.isError && !running) {
        stderr.writeln('Launch failed:\n${launch.text}');
        return true;
      }
      if (running) {
        stdout.writeln(
          launch.text.split('. Nothing was launched').first +
              ' — using it (--relaunch builds it again).',
        );
      }
    }
    final summary = await s.call('get_app_summary', {});
    if (summary.isError) {
      stderr.writeln('No app to check:\n${summary.text}');
      return true;
    }
    final start = currentRoute(summary.text) ?? '/';
    var routes = <String>[
      ...?(argResults!['routes'] as String?)
          ?.split(',')
          .map((r) => r.trim())
          .where((r) => r.isNotEmpty),
    ];
    String? note;
    if (routes.isEmpty) {
      final table = await s.call('get_navigation_stack', {'routes': true});
      routes = routePaths(table.text);
      if (routes.isEmpty) {
        note =
            'Only the current screen was checked: no go_router route table '
            'found. Pass --routes /a,/b to visit more.';
      }
    }
    if (!routes.contains(start)) routes.insert(0, start);

    final screens = <ScreenResult>[];
    for (final route in routes) {
      stdout.writeln('  $route');
      if (route != start || screens.isNotEmpty) {
        final nav = await s.call('navigate_to', {'route': route});
        if (nav.isError) {
          screens.add(
            ScreenResult(
              route,
              audit: 'Could not go to this route: ${nav.text}',
            ),
          );
          continue;
        }
      }
      final audit = await s.call('audit_screen_health', {});
      if (audit.text.startsWith('Not done:')) {
        // The phone is off or locked: every screen would say the same.
        stderr.writeln('\n${audit.text}');
        return true;
      }
      final errors = await s.call('get_errors', {});
      final errorText =
          errors.isError ||
              errors.text.startsWith('No recent errors') ||
              errors.text.startsWith('No errors')
          ? ''
          : errors.text;
      final result = ScreenResult(
        route,
        audit: audit.isError ? 'Audit failed: ${audit.text}' : audit.text,
        errors: errorText,
      );
      String? shotName;
      if (!result.ok) {
        final shot = await s.call('capture_screenshot', {});
        if (shot.images.isNotEmpty) {
          shotName = '${routeFileName(route)}.png';
          File(p.join(out.path, shotName)).writeAsBytesSync(shot.images.first);
        }
      }
      screens.add(
        ScreenResult(
          route,
          audit: result.audit,
          errors: result.errors,
          shot: shotName,
        ),
      );
    }
    if (routes.length > 1) {
      await s.call('navigate_to', {'route': start}); // leave it where it was
    }
    final report = smokeReport(
      screens,
      at: DateTime.now(),
      device: device,
      app: p.basename(project),
      note: note,
    );
    File(p.join(out.path, 'report.md')).writeAsStringSync(report);
    final bad = screens.where((x) => !x.ok).length;
    stdout.writeln(
      bad == 0
          ? '\nAll ${screens.length} screen(s) clean.'
          : '\n$bad of ${screens.length} screen(s) with findings.',
    );
    stdout.writeln('Report: ${p.join(out.path, 'report.md')}');
    return bad > 0;
  }

  /// How to start the server: --server, $FLUTTERPILOT_SERVER, the compiled
  /// one beside this CLI, else `dart run` of its source.
  Future<({String executable, List<String> args, String? workingDirectory})>
  _serverCommand(String project) async {
    final explicit =
        argResults!['server'] as String? ??
        Platform.environment['FLUTTERPILOT_SERVER'];
    final args = ['-p', project];
    if (explicit != null) {
      return (executable: explicit, args: args, workingDirectory: null);
    }
    final dir = await McpInstallCommand.serverPackage(
      argResults!['local'] as String?,
    );
    if (dir == null) {
      usageException(
        'No FlutterPilot server found beside this CLI. Pass --server '
        '<flutterpilot_server executable> or --local <checkout>.',
      );
    }
    final compiled = File(
      p.join(
        dir,
        'build',
        Platform.isWindows ? 'flutterpilot_server.exe' : 'flutterpilot_server',
      ),
    );
    if (compiled.existsSync() && _newerThanSource(compiled, dir)) {
      return (executable: compiled.path, args: args, workingDirectory: null);
    }
    return (
      executable: 'dart',
      args: ['run', p.join(dir, 'bin', 'flutterpilot_server.dart'), ...args],
      workingDirectory: dir,
    );
  }

  /// A compiled server older than its source is not what the checkout says.
  static bool _newerThanSource(File binary, String serverDir) {
    final built = binary.lastModifiedSync();
    try {
      for (final f in Directory(
        p.join(serverDir, 'lib'),
      ).listSync(recursive: true)) {
        if (f is File &&
            f.path.endsWith('.dart') &&
            f.lastModifiedSync().isAfter(built)) {
          return false;
        }
      }
    } catch (_) {}
    return true;
  }
}
