import 'dart:io';
import 'package:args/args.dart';
import 'package:logging/logging.dart' as logging;
import 'package:flutterpilot_server/flutterpilot_server.dart';

void main(List<String> args) async {
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
          'Used by read_dart_file, list_dart_files, and get_build_config. '
          'Defaults to the current working directory.',
    )
    ..addOption(
      'log-level',
      help: 'Log level (fine, info, warning, severe).',
      defaultsTo: 'info',
    );

  final results = parser.parse(args);
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
