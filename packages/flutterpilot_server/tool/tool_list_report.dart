import 'dart:convert';
import 'dart:io';

import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:flutterpilot_server/src/tool_list_report.dart';

/// What each app profile pays for `tools/list`, per tool, sorted by size, so
/// task 04's merges can be chosen from numbers.
///
/// Run from the repository root:
///   dart run packages/flutterpilot_server/tool/tool_list_report.dart
///
/// `--json` writes the same data as JSON. Bytes are the measure
/// `tool_registration_test` budgets (`toolListBytes`), tokens an estimate
/// (bytes / 4).
void main(List<String> args) {
  final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:0');
  final all = server.registeredToolNames;
  final costs = {
    for (final profile in AppProfile.values)
      profile: profileCost(profile, all, server.toolListJson),
  };

  if (args.contains('--json')) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'profiles': {
          for (final MapEntry(key: profile, value: cost) in costs.entries)
            profile.id: {
              'description': profile.description,
              'tools': cost.tools,
              'bytes': cost.bytes,
              'tokens': cost.tokens,
              'perTool': {
                for (final tool in cost.perTool) tool.name: tool.bytes,
              },
            },
        },
      }),
    );
    return;
  }

  for (final MapEntry(key: profile, value: cost) in costs.entries) {
    stdout.writeln(
      '${profile.id}: ${cost.tools} tools, ${_group(cost.bytes)} bytes '
      '(~${_group(cost.tokens)} tokens)',
    );
    for (final tool in cost.perTool) {
      stdout.writeln(
        '  ${tool.name.padRight(28)} ${_group(tool.bytes).padLeft(7)}',
      );
    }
    stdout.writeln();
  }
}

/// `41300` -> `41 300`, the way the report reads.
String _group(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]} ',
);
