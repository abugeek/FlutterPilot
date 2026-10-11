import 'dart:io';

import 'package:args/command_runner.dart';

import '../call_stats.dart';

/// Reports how agents used FlutterPilot in this project, from the call log
/// the MCP server keeps in `.dart_tool/flutterpilot_calls.jsonl`.
class StatsCommand extends Command<void> {
  StatsCommand() {
    argParser.addFlag(
      'clear',
      negatable: false,
      help: 'Delete the call log after printing the report.',
    );
  }

  static const logPath = '.dart_tool/flutterpilot_calls.jsonl';

  @override
  final String name = 'stats';

  @override
  final String description =
      'How agents used FlutterPilot here: tools called, failures, time, and '
      'what followed what (from the MCP server\'s call log; tool names and '
      'timings only).';

  @override
  Future<void> run() async {
    final log = File('${Directory.current.path}/$logPath');
    if (!log.existsSync()) {
      stdout.writeln(
        'No call log here ($logPath). The MCP server writes it while an '
        'agent uses FlutterPilot on this project (off with --no-call-log); '
        'run this in the app folder.',
      );
      return;
    }
    stdout.writeln(callStatsReport(log.readAsLinesSync()));
    if (argResults?['clear'] == true) {
      log.deleteSync();
      stdout.writeln('\nCall log cleared.');
    }
  }
}
