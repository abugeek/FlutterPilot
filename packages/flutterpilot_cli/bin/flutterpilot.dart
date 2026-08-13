import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutterpilot_cli/flutterpilot_cli.dart';

void main(List<String> args) async {
  final runner = CommandRunner<void>(
    'flutterpilot',
    'Official CLI for FlutterPilot — AI-native runtime introspection & dev tooling for Flutter.',
  )
    ..addCommand(InitCommand())
    ..addCommand(DevCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(ExportTestCommand());

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
