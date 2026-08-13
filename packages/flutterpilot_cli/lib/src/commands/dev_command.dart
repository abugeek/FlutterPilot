import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';

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
              stdout.writeln('\n✨ [FlutterPilot] Auto-detected Flutter VM Service: $uri');
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
    exit(exitCode);
  }
}
