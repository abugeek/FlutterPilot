import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:fp_cli/fp_cli.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<void>(
          'flutterpilot',
          'Official CLI for FlutterPilot — AI-native runtime introspection & dev tooling for Flutter.',
        )
        ..addCommand(InitCommand())
        ..addCommand(DevCommand())
        ..addCommand(McpCommand())
        ..addCommand(DoctorCommand())
        ..addCommand(TestCommand())
        ..addCommand(AuditCommand())
        ..addCommand(StatsCommand())
        ..addCommand(SmokeCommand())
        ..addCommand(MigrateCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(e.usage);
    exit(64);
  } catch (e, st) {
    stderr.writeln('Unexpected error: $e\n$st');
    exit(1);
  }
}
