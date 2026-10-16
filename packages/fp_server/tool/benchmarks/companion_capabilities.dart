// Companion Dart MCP server capability inventory (task 10).
//
// Task 10 must verify — not assume — whether the installed companion
// `dart mcp-server` already offers the diagnostics FlutterPilot's reload-error
// fallback provides. This starts that server, performs the MCP handshake, lists
// its tools with their real schemas, and records an inventory. It is read-only:
// it calls no tool, spawns no analysis, and needs no app or network.
//
// Run it from `packages/fp_server`:
//
//   dart run tool/benchmarks/companion_capabilities.dart
//   dart run tool/benchmarks/companion_capabilities.dart --json
library;

import 'dart:convert';
import 'dart:io';

import 'startup_benchmark.dart';

const _schemaVersion = 1;

Future<void> main(List<String> args) async {
  final asJson = args.contains('--json');
  final resultsDir =
      _valueOf(args, '--out') ??
      '${Directory.current.path}${Platform.pathSeparator}benchmark-results';

  final spec = LaunchSpec(
    label: 'companion',
    executable: Platform.resolvedExecutable,
    args: ['mcp-server'],
    workingDirectory: Directory.current.path,
  );

  stdout.writeln('Starting the companion Dart MCP server (read-only)…');
  final session = await StdioBenchmarkSession.start(spec);
  Map<String, dynamic> inventory;
  try {
    final init = await session.initialize(const Duration(seconds: 30));
    final initResult = init['result'] as Map?;
    final tools = await session.request(
      'tools/list',
      null,
      const Duration(seconds: 30),
    );
    final list =
        ((tools['result'] as Map?)?['tools'] as List?) ?? const <Object?>[];

    inventory = {
      'schemaVersion': _schemaVersion,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'protocolVersion': '${initResult?['protocolVersion']}',
      'serverInfo': initResult?['serverInfo'],
      'toolCount': list.length,
      'tools': [
        for (final entry in list)
          if (entry is Map) _toolView(entry.cast<String, dynamic>()),
      ],
      'analysisRelated': [
        for (final entry in list)
          if (entry is Map && _isAnalysisRelated('${entry['name']}'))
            '${entry['name']}',
      ],
    };
  } finally {
    await session.kill();
  }

  Directory(resultsDir).createSync(recursive: true);
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('.', '');
  final path =
      '$resultsDir${Platform.pathSeparator}companion-capabilities-$stamp.json';
  File(
    path,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(inventory));

  if (asJson) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(inventory));
  } else {
    stdout.writeln(
      'companion: ${inventory['serverInfo']} '
      'protocol ${inventory['protocolVersion']}',
    );
    stdout.writeln('tools (${inventory['toolCount']}):');
    for (final t in inventory['tools'] as List) {
      final m = t as Map<String, dynamic>;
      stdout.writeln(
        '  ${m['name']}  [${m['category']}]'
        '${m['required'] == true ? ' (required args)' : ''}',
      );
    }
    stdout.writeln('analysis-related: ${inventory['analysisRelated']}');
    stdout.writeln('report: $path');
  }
}

/// The fields worth recording for an overlap decision: identity, the first line
/// of the description, whether it takes required arguments, and a coarse
/// category. Full schemas are kept for the analysis-related tools only, so the
/// report stays readable.
Map<String, dynamic> _toolView(Map<String, dynamic> tool) {
  final name = '${tool['name']}';
  final schema = (tool['inputSchema'] as Map?)?.cast<String, dynamic>();
  final required = (schema?['required'] as List?)?.isNotEmpty ?? false;
  final description = '${tool['description'] ?? ''}'.split('\n').first.trim();
  return {
    'name': name,
    'description': description.length > 160
        ? '${description.substring(0, 160)}…'
        : description,
    'required': required,
    'category': _category(name),
    if (_isAnalysisRelated(name)) 'inputSchema': schema,
  };
}

/// A coarse category from the tool's name, for grouping the overlap question.
String _category(String name) {
  const analysis = {'analyze', 'lsp', 'diagnostic', 'error', 'fix', 'format'};
  const app = {
    'launch',
    'reload',
    'restart',
    'stop',
    'device',
    'driver',
    'app',
  };
  const project = {'pub', 'create', 'test', 'package', 'symbol', 'grep'};
  final lower = name.toLowerCase();
  for (final key in analysis) {
    if (lower.contains(key)) return 'analysis';
  }
  for (final key in app) {
    if (lower.contains(key)) return 'app';
  }
  for (final key in project) {
    if (lower.contains(key)) return 'project';
  }
  return 'other';
}

bool _isAnalysisRelated(String name) => _category(name) == 'analysis';

String? _valueOf(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
