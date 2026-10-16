import 'dart:convert';
import 'dart:io';

import 'package:fp_server/fp_server.dart';
import 'package:fp_server/src/tool_list_report.dart';

/// What each app profile pays for `tools/list`, per tool, sorted by size, so
/// task 04's merges can be chosen from numbers.
///
/// Run from the repository root:
///   dart run packages/fp_server/tool/tool_list_report.dart
///
/// `--json` writes the same data as JSON.
///
/// Three size units are reported (task 00):
///   * `chars` — the legacy measure (`toolListChars`): the model-facing
///     projection without annotations, in Dart string units. The list-size
///     budgets use this, so a baseline written in chars stays comparable.
///   * `utf8Bytes` — the same projection in UTF-8 bytes, the bytes that cross
///     the wire for the part the model reads.
///   * `wireBytes` — the whole tool object, annotations included.
/// `tokens` is an estimate (UTF-8 bytes / 4), not billed usage.
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
              'chars': cost.chars,
              'utf8Bytes': cost.utf8Bytes,
              'wireBytes': cost.wireBytes,
              'tokens': cost.tokens,
              'perTool': {
                for (final tool in cost.perTool)
                  tool.name: {
                    'chars': tool.chars,
                    'utf8Bytes': tool.utf8Bytes,
                    'wireBytes': tool.wireBytes,
                  },
              },
            },
        },
      }),
    );
    return;
  }

  for (final MapEntry(key: profile, value: cost) in costs.entries) {
    stdout.writeln(
      '${profile.id}: ${cost.tools} tools, ${_group(cost.chars)} chars '
      '(${_group(cost.utf8Bytes)} utf8 bytes, ${_group(cost.wireBytes)} '
      'wire) (~${_group(cost.tokens)} tokens)',
    );
    for (final tool in cost.perTool) {
      stdout.writeln(
        '  ${tool.name.padRight(28)} ${_group(tool.chars).padLeft(7)} '
        'chars  ${_group(tool.utf8Bytes).padLeft(7)} bytes',
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
