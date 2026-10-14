// The eval task set: what to ask, what the answer is, and how to score it
// (task 01 §4-§5). The tasks live in tool/eval/tasks.yaml.
import 'dart:io';

import 'package:yaml/yaml.dart';

enum MatchMode { exact, regex, number }

class EvalTask {
  EvalTask({
    required this.id,
    required this.app,
    required this.prompt,
    required this.answer,
    required this.match,
    this.scenario,
    this.tags = const [],
    this.expectedTools = const [],
    this.maxCalls,
    this.knownHard = false,
  });

  final String id;

  /// A lab app folder name, a sibling of the repo (task 00).
  final String app;
  final String prompt;
  final String answer;
  final MatchMode match;
  final String? scenario;
  final List<String> tags;
  final List<String> expectedTools;

  /// A soft budget, reported, never enforced.
  final int? maxCalls;

  /// A task the current server handles badly on purpose; a failure is a finding.
  final bool knownHard;

  static EvalTask fromYaml(Map<Object?, Object?> yaml) {
    final match = switch ('${yaml['match'] ?? 'exact'}') {
      'exact' => MatchMode.exact,
      'regex' => MatchMode.regex,
      'number' => MatchMode.number,
      final other => throw FormatException('Unknown match mode "$other"'),
    };
    return EvalTask(
      id: '${yaml['id']}',
      app: '${yaml['app']}',
      prompt: '${yaml['prompt']}'.trim(),
      answer: '${yaml['answer']}',
      match: match,
      scenario: yaml['scenario'] == null ? null : '${yaml['scenario']}',
      tags: _strings(yaml['tags']),
      expectedTools: _strings(yaml['expected_tools']),
      maxCalls: yaml['max_calls'] == null
          ? null
          : int.parse('${yaml['max_calls']}'),
      knownHard: yaml['known_hard'] == true,
    );
  }
}

List<String> _strings(Object? value) =>
    value == null ? const [] : [for (final entry in (value as List)) '$entry'];

/// The tasks in [path], in file order.
List<EvalTask> loadTasks(String path) {
  final document = loadYaml(File(path).readAsStringSync());
  if (document is! List) {
    throw FormatException('$path: expected a YAML list of tasks');
  }
  return [
    for (final entry in document)
      EvalTask.fromYaml((entry as Map).cast<Object?, Object?>()),
  ];
}

/// The default start state per app, used when a task names no scenario.
const defaultScenarios = <String, String>{
  'fp_lab_shop': 'eval_base',
  'fp_lab_notes': 'notes_base',
};

/// The model's answer: the text after the last `ANSWER:` line, or null when it
/// wrote none (a missing answer is a failure).
String? extractAnswer(String text) {
  final matches = RegExp(
    'ANSWER:\\s*(.+)',
    caseSensitive: false,
  ).allMatches(text).toList();
  final answer = matches.isEmpty ? null : matches.last.group(1)?.trim();
  return answer == null || answer.isEmpty ? null : answer;
}

/// Whether the extracted [answer] is right for [task].
bool answerMatches(EvalTask task, String? answer) {
  if (answer == null) return false;
  switch (task.match) {
    case MatchMode.exact:
      return _collapse(answer) == _collapse(task.answer);
    case MatchMode.regex:
      return RegExp(
        '^(?:${task.answer})\$',
        caseSensitive: false,
        dotAll: true,
      ).hasMatch(answer.trim());
    case MatchMode.number:
      final got = num.tryParse(answer.replaceAll(',', '').trim());
      final want = num.tryParse(task.answer.replaceAll(',', '').trim());
      return got != null && want != null && got == want;
  }
}

String _collapse(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
