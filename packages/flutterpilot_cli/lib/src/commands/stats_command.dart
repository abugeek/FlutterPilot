import 'dart:io';

import 'package:args/command_runner.dart';

import '../call_stats.dart';

/// Reports how agents used FlutterPilot, from the call log the MCP server
/// keeps in `.dart_tool/flutterpilot_calls.jsonl`.
///
/// `flutterpilot stats [paths...]` takes app folders (the log inside their
/// `.dart_tool`) or log files and combines them; no path reads this folder
/// (task 03 ┬ºC1). The listed-but-never-called tools are sorted by name here:
/// the CLI has no dependency on the server package, so it has no list bytes ΓÇö
/// a caller that does can pass them ([statsTextFor]).
class StatsCommand extends Command<void> {
  StatsCommand() {
    argParser
      ..addFlag(
        'clear',
        negatable: false,
        help: 'Delete the call log(s) after printing the report.',
      )
      ..addFlag('json', negatable: false, help: 'Print the same data as JSON.');
  }

  static const logPath = '.dart_tool/flutterpilot_calls.jsonl';

  @override
  final String name = 'stats';

  @override
  final String description =
      'How agents used FlutterPilot: tools called, failures, time, response '
      'size, what followed what, and what was listed but never called (from '
      'the MCP server\'s call log; tool names and timings only). Takes '
      '[paths...]: app folders or log files to combine.';

  @override
  Future<void> run() async {
    final paths = argResults!.rest;
    final logs = <StatsLog>[];
    final files = <File>[];
    if (paths.isEmpty) {
      final file = File('${Directory.current.path}/$logPath');
      if (!file.existsSync()) {
        stdout.writeln(
          'No call log here ($logPath). The MCP server writes it while an '
          'agent uses FlutterPilot on this project (off with --no-call-log); '
          'run this in the app folder, or pass app folders or log files.',
        );
        return;
      }
      files.add(file);
      logs.add(StatsLog(logPath, file.readAsLinesSync()));
    } else {
      for (final path in paths) {
        final file = _logFileFor(path);
        if (file == null) {
          stdout.writeln('No call log at $path.');
          continue;
        }
        files.add(file);
        logs.add(StatsLog(file.path, file.readAsLinesSync()));
      }
      if (logs.isEmpty) return;
    }

    stdout.writeln(
      argResults!['json'] == true ? statsJsonFor(logs) : statsTextFor(logs),
    );
    if (argResults?['clear'] == true) {
      for (final file in files) {
        file.deleteSync();
      }
      stdout.writeln('\nCall log${files.length == 1 ? '' : 's'} cleared.');
    }
  }

  /// An app folder's log, or a log file itself.
  File? _logFileFor(String path) {
    final file = File(path);
    if (file.existsSync()) return file;
    final dir = Directory(path);
    if (dir.existsSync()) {
      final inDir = File('${dir.path}/$logPath');
      return inDir.existsSync() ? inDir : null;
    }
    return null;
  }
}
