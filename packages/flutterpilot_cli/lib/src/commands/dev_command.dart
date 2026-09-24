import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// Command to run the Flutter app and auto-launch FlutterPilot server.
class DevCommand extends Command<void> {
  @override
  final String name = 'dev';

  @override
  final List<String> aliases = const ['run'];

  @override
  final String description =
      'Runs the Flutter app in debug mode and automatically hooks the FlutterPilot MCP Server.';

  DevCommand() {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Target device id or name (e.g. macos, chrome, emulator-5554, iphone).',
      )
      ..addOption(
        'target',
        abbr: 't',
        help: 'Main entrypoint file path (e.g. lib/main.dart).',
        defaultsTo: 'lib/main.dart',
      );
  }

  void _saveSessionFile(String uri, int pid) {
    try {
      final dartToolDir = Directory(p.join(Directory.current.path, '.dart_tool'));
      if (!dartToolDir.existsSync()) {
        dartToolDir.createSync(recursive: true);
      }
      final sessionFile = File(p.join(dartToolDir.path, 'flutterpilot_session.json'));
      sessionFile.writeAsStringSync(
        jsonEncode({
          'uri': uri,
          'pid': pid,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  void _cleanupSessionFile() {
    try {
      final sessionFile = File(
        p.join(Directory.current.path, '.dart_tool', 'flutterpilot_session.json'),
      );
      if (sessionFile.existsSync()) {
        sessionFile.deleteSync();
      }
    } catch (_) {}
  }

  @override
  Future<void> run() async {
    final device = argResults?['device'] as String?;
    final target = argResults?['target'] as String? ?? 'lib/main.dart';

    final flutterArgs = ['run', '-t', target];
    if (device != null && device.isNotEmpty) {
      flutterArgs.addAll(['-d', device]);
    }

    stdout.writeln('🚀 Starting Flutter app: flutter ${flutterArgs.join(" ")}');

    final process = await Process.start('flutter', flutterArgs, mode: ProcessStartMode.normal);

    final uriRegex = RegExp(r'http://(127\.0\.0\.1|localhost):(\d+)/([a-zA-Z0-9_-]+=*)');
    bool serverStarted = false;

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stdout.writeln(line);

          if (!serverStarted && uriRegex.hasMatch(line)) {
            final match = uriRegex.firstMatch(line);
            if (match != null) {
              serverStarted = true;
              final uri = match.group(0)!;
              _saveSessionFile(uri, process.pid);
              stdout.writeln('\n✨ [FlutterPilot] Auto-detected Flutter VM Service: $uri');
              stdout.writeln('✨ [FlutterPilot] Saved session to .dart_tool/flutterpilot_session.json');
              stdout.writeln('✨ [FlutterPilot] MCP Server is ready to connect with this URI!\n');
            }
          }
        });

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderr.writeln(line);
        });

    // Forward stdin to allow hot-reload (r, R, q) in terminal
    stdin.pipe(process.stdin);

    final exitCode = await process.exitCode;
    _cleanupSessionFile();
    exit(exitCode);
  }
}
