import 'dart:convert';
import 'dart:io';

import 'package:flutterpilot_server/src/call_log.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('fp_calls_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('nothing is written outside a Dart project', () {
    expect(CallLog.inProject(tmp), isNull);
    Directory('${tmp.path}/.dart_tool').createSync();
    expect(CallLog.inProject(tmp)!.file.path, endsWith(CallLog.path));
  });

  test('a call is one line: tool, time, size, and the kind of failure', () {
    final log = CallLog(File('${tmp.path}/calls.jsonl'));
    log.record('tap_widget', ms: 120, isError: false, chars: 800);
    log.record(
      'tap_widget',
      ms: 3004,
      isError: true,
      chars: 300,
      error:
          '[extensionError] Widget not found matching: "Sign Out".\n'
          'HINT: Visible actionable targets: "Secret Account 4421"',
    );
    final lines = log.file.readAsLinesSync().map(jsonDecode).toList();
    expect(lines, hasLength(2));
    expect(lines[0], containsPair('tool', 'tap_widget'));
    expect(lines[0], containsPair('ms', 120));
    expect(lines[0], isNot(contains('err')));
    expect(lines[1]['err'], '[extensionError] Widget not found matching: "…".');
    expect(log.file.readAsStringSync(), isNot(contains('Sign Out')));
    expect(log.file.readAsStringSync(), isNot(contains('4421')));
  });

  test('what the app or agent wrote is not kept in a failure kind', () {
    expect(
      CallLog.failureKind(
        "Query failed: no such column: status sql 'SELECT pin FROM users' args []",
      ),
      'Query failed: no such column: status sql "…" args []',
    );
    expect(
      CallLog.failureKind(
        'No answer from the app within 30 s. The app\'s busy',
      ),
      "No answer from the app within N s. The app's busy",
    );
  });

  test('a full log keeps its newer half', () {
    final log = CallLog(File('${tmp.path}/calls.jsonl'), maxBytes: 2000);
    for (var i = 0; i < 60; i++) {
      log.record('tool_$i', ms: 1, isError: false, chars: 1);
    }
    final text = log.file.readAsStringSync();
    expect(text.length, lessThan(4000));
    expect(text, contains('tool_59'));
    expect(text, isNot(contains('"tool_0"')));
  });
}
