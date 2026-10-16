// Tests for the read-only inspection suite (task 05 §12). They are free: no
// key, no app. They cover the schema and its refusals, the acceptance rules
// (ten verified cases across the required categories), shuffle independence,
// the optional XML export's consistency, and the argument-aware read-only
// policy that keeps the model from mutating the fixture.
import 'dart:io';
import 'dart:math';

import 'package:fp_server/src/tool_annotations.dart';
import 'package:test/test.dart';

import '../tool/eval/src/inspection.dart';
import '../tool/eval/src/mcp_session.dart';
import '../tool/eval/src/policy.dart';

/// The shipped suite, so its wording and categories are validated too.
String get _shippedSuitePath =>
    '${Directory.current.path}/tool/eval/inspection_tasks.yaml';

/// A well-formed ten-question suite that satisfies every acceptance rule, with
/// optional surgery for the negative cases.
String _completeSuite({String? dropId, String? replace}) {
  const categories = [
    'discovery',
    'ui',
    'ui',
    'diagnostics',
    'diagnostics',
    'state',
    'state',
    'storage',
    'storage',
    'zero_code',
  ];
  final buffer = StringBuffer()
    ..writeln('version: 1')
    ..writeln('name: fixture');
  buffer.writeln('questions:');
  for (var i = 0; i < categories.length; i++) {
    final id = 'q${i + 1}';
    if (id == dropId) continue;
    buffer
      ..writeln('  - id: $id')
      ..writeln('    app: fp_lab_shop')
      ..writeln('    category: ${categories[i]}')
      ..writeln('    scenario: eval_base')
      ..writeln('    initial_state: eval_base loaded')
      ..writeln('    question: Question number ${i + 1}?')
      ..writeln('    answer: a${i + 1}')
      ..writeln('    match: exact')
      ..writeln('    verified: true')
      ..writeln('    evidence:')
      ..writeln('      - call: get_app_summary')
      ..writeln('        result: answer a${i + 1}');
  }
  if (replace != null) buffer.writeln(replace);
  return buffer.toString();
}

InspectionSuite _loadText(String text) {
  final dir = Directory.systemTemp.createTempSync('inspection-suite-test');
  final file = File('${dir.path}/suite.yaml')..writeAsStringSync(text);
  try {
    return loadInspectionSuite(file.path);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// A session that records calls, so a refusal can be proven not to reach it.
class _RecordingClient implements McpClient {
  final calls = <String>[];
  final arguments = <Map<String, dynamic>>[];

  @override
  String get instructions => '';

  @override
  List<McpTool> get tools => const [];

  @override
  Stream<List<McpTool>> get toolListChanges => const Stream.empty();

  @override
  Future<McpCallResult> call(String name, [Map<String, dynamic>? a]) async {
    calls.add(name);
    arguments.add(a ?? const {});
    return McpCallResult(
      [
        {'type': 'text', 'text': 'observed $name'},
      ],
      false,
      1,
      10,
    );
  }
}

void main() {
  group('schema', () {
    test('the shipped suite is a complete, verified ten-question suite', () {
      final suite = loadInspectionSuite(_shippedSuitePath);
      expect(suite.version, 1);
      expect(suite.questions, hasLength(InspectionSuite.requiredCount));
      expect(suite.questions.map((q) => q.id).toSet(), hasLength(10));
      expect(suite.acceptanceProblems(), isEmpty);
      expect(suite.isAccepted, isTrue);
      for (final q in suite.questions) {
        expect(q.verified, isTrue, reason: q.id);
        expect(q.answer, isNotEmpty, reason: q.id);
        expect(q.evidence, isNotEmpty, reason: q.id);
        expect(q.initialState, isNotNull, reason: q.id);
        expect(q.scenario, isNotNull, reason: q.id);
      }
    });

    test('a verified question needs an answer', () {
      expect(
        () => _loadText(
          'version: 1\nquestions:\n'
          '  - id: q1\n    app: fp_lab_shop\n    category: ui\n'
          '    question: What?\n    verified: true\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('verified questions need an "answer"'),
          ),
        ),
      );
    });

    test('an answer without verification is refused', () {
      expect(
        () => _loadText(
          'version: 1\nquestions:\n'
          '  - id: q1\n    app: fp_lab_shop\n    category: ui\n'
          '    question: What?\n    answer: guessed\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('must not be committed'),
          ),
        ),
      );
    });

    test('a verified question needs evidence', () {
      expect(
        () => _loadText(
          'version: 1\nquestions:\n'
          '  - id: q1\n    app: fp_lab_shop\n    category: ui\n'
          '    question: What?\n    answer: a\n    verified: true\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('verified questions need "evidence"'),
          ),
        ),
      );
    });

    test('an invalid match mode is named', () {
      expect(
        () => _loadText(
          'version: 1\nquestions:\n'
          '  - id: q1\n    app: fp_lab_shop\n    category: ui\n'
          '    question: What?\n    match: fuzzy\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Unknown match mode "fuzzy"'),
          ),
        ),
      );
    });

    test('an invalid category is named', () {
      expect(
        () => _loadText(
          'version: 1\nquestions:\n'
          '  - id: q1\n    app: fp_lab_shop\n    category: vibes\n'
          '    question: What?\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Unknown category "vibes"'),
          ),
        ),
      );
    });

    test('an unsupported version is refused', () {
      expect(
        () => _loadText('version: 2\nquestions: []\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('unsupported version'),
          ),
        ),
      );
    });

    test('a missing id is named', () {
      expect(
        () => _loadText(
          'version: 1\nquestions:\n  - app: fp_lab_shop\n    category: ui\n'
          '    question: What?\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('needs an "id"'),
          ),
        ),
      );
    });
  });

  group('acceptance', () {
    test('a complete verified suite is accepted', () {
      final suite = _loadText(_completeSuite());
      expect(suite.acceptanceProblems(), isEmpty);
      expect(suite.isAccepted, isTrue);
    });

    test('nine questions are not ten', () {
      final suite = _loadText(_completeSuite(dropId: 'q10'));
      expect(
        suite.acceptanceProblems(),
        contains('expected 10 questions, found 9'),
      );
      expect(
        suite.acceptanceProblems(),
        contains('no verified case covers zero_code'),
      );
    });

    test('an unverified case blocks acceptance and names itself', () {
      final suite = _loadText(
        _completeSuite(
          replace:
              '  - id: q11\n    app: fp_lab_shop\n    category: ui\n'
              '    question: Who?\n',
        ),
      );
      expect(
        suite.acceptanceProblems(),
        containsAll(['expected 10 questions, found 11', 'q11: not verified']),
      );
    });

    test('a duplicate id is flagged', () {
      final suite = _loadText(
        _completeSuite(
          replace:
              '  - id: q1\n    app: fp_lab_shop\n    category: ui\n'
              '    question: Again?\n',
        ),
      );
      expect(suite.acceptanceProblems(), contains('duplicate id "q1"'));
    });

    test('each required category group must be covered', () {
      // Only diagnostics and state: three groups are missing.
      final suite = _loadText(
        'version: 1\nquestions:\n'
        '  - id: a\n    app: fp_lab_shop\n    category: diagnostics\n'
        '    question: What?\n',
      );
      expect(
        suite.acceptanceProblems(),
        containsAll([
          'no verified case covers discovery',
          'no verified case covers ui',
          'no verified case covers state/storage',
          'no verified case covers zero_code',
        ]),
      );
    });
  });

  group('shuffle independence', () {
    test('any order keeps the same self-contained cases', () {
      final suite = loadInspectionSuite(_shippedSuitePath);
      final ids = suite.questions.map((q) => q.id).toSet();
      final shuffled = [...suite.questions]..shuffle(Random(7));
      expect(shuffled.map((q) => q.id).toSet(), ids);
      expect(shuffled, hasLength(suite.questions.length));
      // Self-contained: every case names its app, scenario and initial state,
      // so it never depends on what another case left behind.
      for (final q in shuffled) {
        expect(q.app, isNotEmpty);
        expect(q.scenario, isNotNull);
        expect(q.initialState, isNotNull);
      }
    });

    test('loading is deterministic', () {
      final a = loadInspectionSuite(_shippedSuitePath);
      final b = loadInspectionSuite(_shippedSuitePath);
      expect(
        a.questions.map((q) => q.id).toList(),
        b.questions.map((q) => q.id).toList(),
      );
    });

    test('a question maps onto the workflow-suite shape for the runner', () {
      final suite = _loadText(_completeSuite());
      final task = suite.questions.first.toEvalTask();
      expect(task.id, suite.questions.first.id);
      expect(task.prompt, suite.questions.first.question);
      expect(task.answer, suite.questions.first.answer);
      expect(task.tags, [suite.questions.first.category.name]);
    });
  });

  group('xml export', () {
    test('one testcase per question with matching answers', () {
      final suite = _loadText(_completeSuite());
      final xml = inspectionSuiteToXml(suite);
      expect(xml, contains('tests="10"'));
      expect(xml, contains('verified="10"'));
      for (final q in suite.questions) {
        expect(xml, contains('<testcase id="${q.id}"'));
        expect(xml, contains('<answer>${q.answer}</answer>'));
      }
      expect(
        RegExp(r'<testcase ').allMatches(xml).length,
        suite.questions.length,
      );
    });

    test('text and attributes are escaped', () {
      final suite = _loadText(
        'version: 1\nquestions:\n'
        '  - id: q1\n    app: fp_lab_shop\n    category: ui\n'
        "    question: 'Which is \"a\" & <b>?'\n"
        "    answer: 'a&b<c>'\n"
        '    verified: true\n    evidence:\n'
        "      - call: 'inspect_widget(key: \"x\")'\n"
        "        result: '<ok & fine>'\n",
      );
      final xml = inspectionSuiteToXml(suite);
      expect(xml, contains('Which is &quot;a&quot; &amp; &lt;b&gt;?'));
      expect(xml, contains('<answer>a&amp;b&lt;c&gt;</answer>'));
      expect(xml, contains('call="inspect_widget(key: &quot;x&quot;)"'));
      expect(xml, contains('&lt;ok &amp; fine&gt;'));
      expect(xml, isNot(contains('<b>')));
    });
  });

  group('read-only policy', () {
    test('plain reads are allowed', () {
      for (final name in [
        'get_app_summary',
        'get_widget_tree',
        'inspect_widget',
        'get_errors',
        'get_network_logs',
        'exec_sql_query',
        'get_hive_contents',
        'get_shared_preferences',
        'get_state',
        'get_debug_logs',
        'get_http_profile',
        'audit_screen_health',
      ]) {
        expect(
          isReadOnlyCall(name, const {}),
          isTrue,
          reason: '$name should be a read',
        );
      }
    });

    test('clears, sweeps and driving tools are refused', () {
      final refused = <String, Map<String, dynamic>>{
        'get_state': {'clear': true},
        'get_debug_logs': {'clear': 'true'},
        'get_http_profile': {'clear': true},
        'audit_screen_health': {
          'routes': ['/', '/cart'],
        },
        'navigate_to': {'route': '/cart'},
        'set_app_settings': {'theme': 'dark'},
        'mock_http_response': {'url_pattern': '/products'},
        'simulate_network': {'condition': 'none'},
        'scenario': {'load': 'eval_base'},
        'profile_action': {'tool': 'tap_widget'},
        'get_memory_details': {'cycle': <dynamic>[]},
        'call_custom_tool': {'name': 'x'},
        'tap_widget': {'key': 'x'},
        'enter_text': {'key': 'x', 'text': 'y'},
        'hot_reload': {'restart': true},
        'set_state': {'path': 'x', 'value': 'y'},
        'set_shared_preference': {'key': 'k', 'value': 'v'},
        'set_secure_storage_key': {'key': 'k', 'value': 'v'},
        'generate_test': {'steps': <dynamic>[]},
        'compare_screenshot': {'name': 'x'},
        'verify_feature': {'name': 'x'},
        'connect_app': {'uri': 'x'},
        'launch_app': {'device': 'windows'},
        'switch_device': {'id': 'x'},
        'run_on_devices': {
          'devices': ['a'],
        },
        'execute_action_chain': {
          'steps': [
            {'tool': 'get_app_summary', 'arguments': <dynamic>{}},
          ],
        },
      };
      for (final entry in refused.entries) {
        expect(
          isReadOnlyCall(entry.key, entry.value),
          isFalse,
          reason: '${entry.key} ${entry.value} should be refused',
        );
      }
    });

    test('a nested mutating step is refused and named', () {
      final refusal = readOnlyRefusalFor('execute_action_chain', {
        'steps': [
          {'tool': 'get_app_summary', 'arguments': <dynamic>{}},
          {
            'tool': 'navigate_to',
            'arguments': {'route': '/cart'},
          },
        ],
      });
      expect(refusal, isNotNull);
      expect(refusal, contains('navigate_to'));
    });

    test('a clear-capable tool is allowed without the clearing argument', () {
      expect(isReadOnlyCall('get_debug_logs', const {'limit': 300}), isTrue);
      expect(
        isReadOnlyCall('audit_screen_health', const {'label': 'x'}),
        isTrue,
      );
    });

    test('the wrapper refuses without reaching the session', () async {
      final inner = _RecordingClient();
      final client = ReadOnlyPolicyClient(inner);
      final refused = await client.call('navigate_to', {'route': '/cart'});
      expect(refused.isError, isTrue);
      expect(refused.text, contains('Refused'));
      expect(inner.calls, isEmpty);

      final allowed = await client.call('get_app_summary');
      expect(allowed.isError, isFalse);
      expect(inner.calls, ['get_app_summary']);
    });

    test('the deny set is derived from the reviewed effects', () {
      // Every `reads` tool is allowed, plus the observing mode of the four
      // clear-capable tools; a `destructive` tool is never a read.
      const observing = {
        'get_state',
        'get_debug_logs',
        'get_http_profile',
        'audit_screen_health',
      };
      for (final entry in toolEffects.entries) {
        final expected =
            entry.value == ToolEffect.reads || observing.contains(entry.key);
        expect(
          isReadOnlyCall(entry.key, const {}),
          expected,
          reason: '${entry.key} (${entry.value.name})',
        );
      }
      for (final name in destructiveToolNames) {
        expect(isReadOnlyCall(name, const {}), isFalse);
      }
    });
  });
}
