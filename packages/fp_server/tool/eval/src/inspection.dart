// The read-only inspection suite (task 05): what to ask, the verified answer,
// how it is scored, and the evidence that the answer is real.
//
// The workflow suite (tasks.yaml) drives the app; this suite only observes it.
// Keeping it separate means a curated inspection surface can be measured
// without relabelling a mutating workflow as read-only (task 05 §2–§3), and the
// runner selects whichever suite is being measured.
//
// The suite is canonical in YAML (`inspection_tasks.yaml`). XML is an optional
// export for external tooling, generated from the same entries, never a second
// source of truth (task 05 §11).
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'tasks.dart';

/// The categories the ten-case suite must cover (task 05 §9): discovery, UI,
/// diagnostics, state/storage and zero-code.
enum InspectionCategory { discovery, ui, diagnostics, state, storage, zeroCode }

/// Maps the YAML spelling to a category, or throws naming the offender.
InspectionCategory inspectionCategoryOf(String name) => switch (name) {
  'discovery' => InspectionCategory.discovery,
  'ui' => InspectionCategory.ui,
  'diagnostics' => InspectionCategory.diagnostics,
  'state' => InspectionCategory.state,
  'storage' => InspectionCategory.storage,
  'zero_code' => InspectionCategory.zeroCode,
  final other => throw FormatException('Unknown category "$other"'),
};

/// The category groups acceptance requires, and the accepted spellings of each
/// (task 05 §9). `state/storage` accepts either.
const requiredCategoryGroups = <String, Set<InspectionCategory>>{
  'discovery': {InspectionCategory.discovery},
  'ui': {InspectionCategory.ui},
  'diagnostics': {InspectionCategory.diagnostics},
  'state/storage': {InspectionCategory.state, InspectionCategory.storage},
  'zero_code': {InspectionCategory.zeroCode},
};

/// One minimal, sanitized manual observation that proves an answer: the call
/// made and the response that settles it (task 05 §7).
class InspectionEvidence {
  const InspectionEvidence({required this.call, required this.result});

  /// The single MCP call, e.g. `inspect_widget(key: "fav_button")`.
  final String call;

  /// The relevant response line(s), sanitized.
  final String result;

  Map<String, Object?> toJson() => {'call': call, 'result': result};

  static InspectionEvidence fromYaml(Object? yaml) {
    if (yaml is! Map) {
      throw const FormatException('evidence entries must be {call, result}');
    }
    final call = '${yaml['call'] ?? ''}'.trim();
    final result = '${yaml['result'] ?? ''}'.trim();
    if (call.isEmpty || result.isEmpty) {
      throw const FormatException('evidence needs both "call" and "result"');
    }
    return InspectionEvidence(call: call, result: result);
  }
}

/// One inspection question and its verified answer.
class InspectionQuestion {
  InspectionQuestion({
    required this.id,
    required this.app,
    required this.category,
    required this.question,
    required this.answer,
    required this.match,
    this.scenario,
    this.verified = false,
    this.evidence = const [],
    this.platforms = const ['windows'],
    this.initialState,
    this.maxCalls,
  });

  final String id;
  final String app;
  final InspectionCategory category;

  /// The question put to the model, phrased so it ends with `ANSWER: …`.
  final String question;

  /// The exact expected answer; empty when [verified] is false.
  final String answer;
  final MatchMode match;
  final String? scenario;

  /// Whether the answer was reproduced through MCP from a reset state.
  final bool verified;

  /// The manual calls that proved the answer.
  final List<InspectionEvidence> evidence;

  /// The platforms the answer was confirmed on.
  final List<String> platforms;

  /// A short description of the reproducible initial state (scenario + any
  /// setup fingerprint) so cases have no inter-case dependency (task 05 §9).
  final String? initialState;

  /// A soft budget, reported, never enforced.
  final int? maxCalls;

  /// The workflow-suite shape of this question, so the runner, report and
  /// scoring are reused unchanged.
  EvalTask toEvalTask() => EvalTask(
    id: id,
    app: app,
    prompt: question,
    answer: answer,
    match: match,
    scenario: scenario,
    tags: [category.name],
    maxCalls: maxCalls,
  );

  static InspectionQuestion fromYaml(Map<Object?, Object?> yaml) {
    final id = '${yaml['id'] ?? ''}'.trim();
    if (id.isEmpty) throw const FormatException('a question needs an "id"');
    final app = '${yaml['app'] ?? ''}'.trim();
    if (app.isEmpty) throw FormatException('$id: needs an "app"');
    final question = '${yaml['question'] ?? ''}'.trim();
    if (question.isEmpty) throw FormatException('$id: needs a "question"');
    final verified = yaml['verified'] == true;
    final answer = '${yaml['answer'] ?? ''}'.trim();
    if (verified && answer.isEmpty) {
      throw FormatException('$id: verified questions need an "answer"');
    }
    if (!verified && answer.isNotEmpty) {
      throw FormatException(
        '$id: has an answer but is not marked verified; an unverified answer '
        'must not be committed',
      );
    }
    final evidence = [
      for (final entry in (yaml['evidence'] as List? ?? const []))
        InspectionEvidence.fromYaml(entry),
    ];
    if (verified && evidence.isEmpty) {
      throw FormatException('$id: verified questions need "evidence"');
    }
    return InspectionQuestion(
      id: id,
      app: app,
      category: inspectionCategoryOf('${yaml['category'] ?? ''}'.trim()),
      question: question,
      answer: answer,
      match: matchModeOf('${yaml['match'] ?? 'exact'}'),
      scenario: yaml['scenario'] == null ? null : '${yaml['scenario']}'.trim(),
      verified: verified,
      evidence: evidence,
      platforms: _strings(yaml['platforms']).isEmpty
          ? const ['windows']
          : _strings(yaml['platforms']),
      initialState: yaml['initial_state'] == null
          ? null
          : '${yaml['initial_state']}'.trim(),
      maxCalls: yaml['max_calls'] == null
          ? null
          : int.parse('${yaml['max_calls']}'),
    );
  }
}

/// The parsed, validated inspection suite.
class InspectionSuite {
  InspectionSuite({
    required this.version,
    required this.name,
    required this.questions,
  });

  /// The schema version this build reads.
  static const supportedVersion = 1;

  /// The exact number of active, verified cases acceptance requires.
  static const requiredCount = 10;

  final int version;
  final String name;
  final List<InspectionQuestion> questions;

  List<InspectionQuestion> get verifiedQuestions => [
    for (final q in questions)
      if (q.verified) q,
  ];

  /// Whether the suite meets every acceptance rule: ten questions, each
  /// verified with an answer and evidence, covering every required category
  /// (task 05 §9).
  bool get isAccepted => acceptanceProblems().isEmpty;

  /// Why the suite is not yet acceptable; empty when it is. Reported, never
  /// thrown: a proposed suite is allowed to be incomplete, but a paid run
  /// refuses it.
  List<String> acceptanceProblems() {
    final problems = <String>[];
    if (questions.length != requiredCount) {
      problems.add(
        'expected $requiredCount questions, found ${questions.length}',
      );
    }
    final ids = <String>{};
    for (final q in questions) {
      if (!ids.add(q.id)) problems.add('duplicate id "${q.id}"');
    }
    for (final q in questions) {
      if (!q.verified) problems.add('${q.id}: not verified');
      if (q.verified && q.answer.isEmpty) {
        problems.add('${q.id}: verified but has no answer');
      }
      if (q.verified && q.evidence.isEmpty) {
        problems.add('${q.id}: verified but has no evidence');
      }
    }
    final covered = {for (final q in verifiedQuestions) q.category};
    for (final group in requiredCategoryGroups.entries) {
      if (!group.value.any(covered.contains)) {
        problems.add('no verified case covers ${group.key}');
      }
    }
    return problems;
  }
}

/// Loads and validates the inspection suite in [path]. Throws a
/// [FormatException] naming the first structural problem; acceptance
/// ([InspectionSuite.isAccepted]) is reported separately so an incomplete but
/// well-formed proposed suite still loads for review and tests.
InspectionSuite loadInspectionSuite(String path) {
  final document = loadYaml(File(path).readAsStringSync());
  if (document is! Map) {
    throw FormatException(
      '$path: expected a YAML mapping with version, name and questions',
    );
  }
  final version = document['version'];
  if (version is! int || version != InspectionSuite.supportedVersion) {
    throw FormatException(
      '$path: unsupported version "$version" '
      '(expected ${InspectionSuite.supportedVersion})',
    );
  }
  final questions = document['questions'];
  if (questions is! List) {
    throw FormatException('$path: expected a "questions" list');
  }
  return InspectionSuite(
    version: version,
    name: '${document['name'] ?? 'inspection'}',
    questions: [
      for (final entry in questions)
        InspectionQuestion.fromYaml((entry as Map).cast<Object?, Object?>()),
    ],
  );
}

/// The suite as JUnit-style XML question/answer pairs for external tooling
/// (task 05 §11). Every text node and attribute is escaped; the YAML stays
/// canonical and this is generated from the parsed entries.
String inspectionSuiteToXml(InspectionSuite suite) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<testsuite name="${_xml(suite.name)}" '
      'version="${suite.version}" tests="${suite.questions.length}" '
      'verified="${suite.verifiedQuestions.length}">',
    );
  for (final q in suite.questions) {
    buffer.writeln(
      '  <testcase id="${_xml(q.id)}" app="${_xml(q.app)}" '
      'category="${_xml(q.category.name)}" match="${_xml(q.match.name)}" '
      'verified="${q.verified}">',
    );
    buffer.writeln('    <question>${_xml(q.question)}</question>');
    buffer.writeln('    <answer>${_xml(q.answer)}</answer>');
    for (final evidence in q.evidence) {
      buffer.writeln(
        '    <evidence call="${_xml(evidence.call)}">'
        '${_xml(evidence.result)}</evidence>',
      );
    }
    buffer.writeln('  </testcase>');
  }
  buffer.writeln('</testsuite>');
  return buffer.toString();
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

List<String> _strings(Object? value) => value == null
    ? const []
    : [for (final entry in (value as List)) '$entry'.trim()];
