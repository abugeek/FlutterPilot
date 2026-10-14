import 'dart:io';
import 'package:args/args.dart';
import 'package:logging/logging.dart' as logging;

import '../flutterpilot_server.dart';
import 'app_launcher.dart';
import 'tool_profiles.dart';

/// The `flutterpilot_server` command: parses [args], starts the MCP server
/// on stdio and runs until SIGINT. The executable (bin/) is just this, so a
/// package that depends on flutterpilot_server can compile the same server
/// (what `flutterpilot mcp install` does when the CLI came from pub.dev).
Future<void> runFlutterPilotServer(List<String> args) async {
  // launch_app's detached helper: runs the app's launch command and keeps
  // its output and pid on disk (app_launcher.dart).
  if (args.isNotEmpty && args.first == superviseFlag) {
    exit(await superviseLaunch(args.sublist(1)));
  }
  final parser = ArgParser()
    ..addOption(
      'uri',
      abbr: 'u',
      help: 'The VM Service URI of the running Flutter app.',
    )
    ..addFlag(
      'allow-destructive',
      abbr: 'd',
      help: 'Allow non-SELECT queries on databases.',
      negatable: false,
    )
    ..addFlag(
      'allow-remote',
      help:
          'Allow connecting to non-local VM Service endpoints. Use only with authenticated/private networks.',
      negatable: false,
    )
    ..addOption(
      'remote-token',
      help:
          'Optional additional token that must match the VM-service URI path when using --allow-remote.',
    )
    ..addOption(
      'project-root',
      abbr: 'p',
      help:
          'Path to the Flutter project root (where pubspec.yaml lives). '
          'Used to find the app flutter run started there. '
          'Defaults to the current working directory.',
    )
    ..addFlag(
      'static-tools',
      help:
          'List every tool from the start and never change the list. For MCP '
          "clients that don't refresh it after tools/list_changed (they would "
          'keep a stale list); a tool that cannot work on the connected app '
          'says why when called.',
      negatable: false,
    )
    ..addOption(
      'tools',
      allowed: ['core', 'all'],
      defaultsTo: 'all',
      help:
          'Which tools to list. "core": a short set for a client that counts '
          'tools across every server it runs (Cursor: ~40); "all" (default): '
          'every tool that works for the app.',
    )
    ..addFlag(
      'call-log',
      defaultsTo: true,
      help:
          'Note each tool call (name, time, size, kind of failure; no '
          'arguments or results) in the project\'s '
          '.dart_tool/flutterpilot_calls.jsonl for "flutterpilot stats".',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
    ..addOption(
      'log-level',
      help: 'Log level (fine, info, warning, severe).',
      defaultsTo: 'info',
    );

  final results = parser.parse(args);
  if (results['help'] as bool) {
    stdout.writeln(
      'flutterpilot_server: the FlutterPilot MCP server (stdio). An MCP '
      'client starts it; "flutterpilot mcp install" writes the config.\n\n'
      '${parser.usage}',
    );
    return;
  }
  final uri = results['uri'] as String?;
  final allowDestructive = results['allow-destructive'] as bool;
  final allowRemote = results['allow-remote'] as bool;
  final remoteToken = results['remote-token'] as String?;
  final projectRootArg = results['project-root'] as String?;
  final projectRoot = projectRootArg != null ? Directory(projectRootArg) : null;

  // Configure structured logging — all output goes to stderr (stdout is MCP JSON-RPC).
  _setupLogging(results['log-level'] as String);

  if (uri == null) {
    stderr.writeln(
      'ℹ️ No --uri provided. FlutterPilot will auto-discover running Flutter debug sessions.',
    );
  }

  final server = FlutterPilotServer(
    vmServiceUri: uri,
    allowDestructive: allowDestructive,
    allowRemoteConnections: allowRemote,
    remoteAccessToken: remoteToken,
    projectRoot: projectRoot,
    staticTools: results['static-tools'] as bool,
    toolProfile: ToolProfile.byName(results['tools'] as String),
    callLog: results['call-log'] as bool,
  );

  // Handle graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    logging.Logger('main').info('Shutting down FlutterPilot server...');
    await server.stop();
    exit(0);
  });

  try {
    await server.start();
  } catch (e, st) {
    logging.Logger('main').severe('Error starting server', e, st);
    exit(1);
  }
}

void _setupLogging(String levelName) {
  final level = switch (levelName.toLowerCase()) {
    'fine' || 'debug' => logging.Level.FINE,
    'warning' || 'warn' => logging.Level.WARNING,
    'severe' || 'error' => logging.Level.SEVERE,
    _ => logging.Level.INFO,
  };
  logging.Logger.root.level = level;
  logging.Logger.root.onRecord.listen((record) {
    final time = record.time.toIso8601String().substring(11, 23);
    final msg =
        '[$time] ${record.level.name} [${record.loggerName}] ${record.message}';
    if (record.error != null) {
      stderr.writeln('$msg\n  ${record.error}');
      if (record.stackTrace != null) stderr.writeln('  ${record.stackTrace}');
    } else {
      stderr.writeln(msg);
    }
  });
}
