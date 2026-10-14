/// Machine-readable twins of the verdict tools' text results (MCP
/// `structuredContent`): `assert_widget`, `wait_for`, `verify_feature` and
/// `run_on_devices`.
///
/// A program (CI, `flutterpilot smoke`, `run_on_devices`' own comparison, a
/// reviewer script) reads `{"passed": false, ...}` instead of parsing prose.
/// The text content is unchanged — models read that — and no `outputSchema` is
/// declared: the four schemas would add bytes to every session's `tools/list`
/// for shapes that are small and documented in `TOOLS.generated.md`. Without a
/// declared schema mcp_dart does not validate, so each shape below must stay
/// in step with the tool that builds it, which the tests check.
library;

import 'package:mcp_dart/mcp_dart.dart';

import 'fleet_compare.dart';
import 'redaction.dart';
import 'verification.dart';

/// Every tool that returns a structured result, and its shape, read by
/// `tool/generate_tools_doc.dart` into `TOOLS.generated.md`.
const structuredShapes = <String, String>{
  'assert_widget':
      '{passed: bool, check: "text"|"key"|"enabled"|"disabled"|"count"|"none", '
      'expected?: string, found?: int, reason?: string}',
  'wait_for':
      '{met: bool, waitedMs: int, timedOut: bool, condition: "key"|"route"|'
      '"state"|"frames"|"animations"|"none", route?: string}',
  'verify_feature':
      '{feature: string, criteria: [{index: int, text: string, verdict: '
      '"passed"|"failed"|"not_verified", warnings: int}], report: string} '
      '(finish: true only)',
  'run_on_devices':
      '{devices: [{id: string, passedSteps: int, totalSteps: int, '
      'failedStep?: int, route?: string, errors: int}], same: bool}',
};

/// [result] rebuilt with new [content] (and optionally [isError]), keeping its
/// structured content.
///
/// The wrappers that rebuild a result on its way out (the batch-nudge tip, the
/// image down-scaling, the phone state, the native crash, the hang diagnosis)
/// must not drop what a program reads.
CallToolResult keepingStructured(
  CallToolResult result, {
  required List<Content> content,
  bool? isError,
}) => CallToolResult(
  content: content,
  isError: isError ?? result.isError,
  structuredContentJson: result.structuredContentJson,
);

/// [result] with [structured] attached; the text is left as it is.
///
/// An error result still carries its verdict (`assert_widget` failing is
/// `{passed: false, ...}`, not nothing): a caller deciding what to do next
/// reads it either way.
CallToolResult withVerdict(
  CallToolResult result,
  Map<String, dynamic> structured,
) => CallToolResult(
  content: result.content,
  isError: result.isError,
  structuredContent: structured,
);

/// `assert_widget`'s structured result: what was checked, whether it held, and
/// what the check saw.
///
/// `found` is the number the check saw — 1 for a text, key or enabled check
/// that passed, the widget count for a count check — and is left out when the
/// check failed: the extension answers a failed assertion with its message,
/// not with a count, and the server does not read the count back out of the
/// message. `reason` is that message.
Map<String, dynamic> assertWidgetVerdict({
  required String check,
  String? expected,
  required bool passed,
  int? found,
  String? reason,
}) => {
  'passed': passed,
  'check': check,
  if (expected != null) 'expected': Redaction.text(expected),
  'found': ?found,
  if (reason != null) 'reason': Redaction.text(reason),
};

/// `wait_for`'s structured result: whether the condition held, how long it
/// waited, whether it ran out its deadline, and which condition it was.
///
/// `timedOut` is `waitedMs` reaching the timeout the extension was given: the
/// SDK's own timeout answer is an error whose message says so, and reading
/// that message back would be parsing the text. A wait that failed for another
/// reason (no app, a refusal) returns long before its deadline.
Map<String, dynamic> waitForVerdict({
  required String condition,
  required bool met,
  required int waitedMs,
  required int timeoutMs,
}) => {
  'met': met,
  'waitedMs': waitedMs,
  'timedOut': !met && timeoutMs > 0 && waitedMs >= timeoutMs,
  'condition': condition,
};

/// `verify_feature(finish: true)`'s text and structured result.
///
/// The other `verify_feature` calls (start, picking a criterion, an error) are
/// not verdicts and carry no structured content.
({String text, Map<String, dynamic> structured}) verifyFeatureResult(
  Verification v,
  String reportPath,
) => (
  text: [
    '${v.feature}: ${v.headline}.',
    for (final c in v.criteria)
      '${c.index}. ${c.verdict.label} ${c.text} — ${c.reason}',
    'Report: $reportPath (with a screenshot per criterion).',
  ].join('\n'),
  structured: {
    'feature': v.feature,
    'criteria': [
      for (final c in v.criteria)
        {
          'index': c.index,
          'text': c.text,
          'verdict': switch (c.verdict) {
            Verdict.pass => 'passed',
            Verdict.fail => 'failed',
            Verdict.unverified => 'not_verified',
          },
          'warnings': c.warnings.length,
        },
    ],
    'report': reportPath,
  },
);

/// `run_on_devices`' structured result: how each device did and whether they
/// agreed.
///
/// `failedStep` is the 1-based step that device stopped at, and `route` is the
/// route it ended on. A device with 0 passed, no failed step and no route was
/// not reachable at all (its reason stays in the text).
Map<String, dynamic> fleetVerdict(
  List<DeviceRun> runs, {
  required int stepsRequested,
  required bool same,
}) => {
  'devices': [for (final r in runs) _deviceVerdict(r, stepsRequested)],
  'same': same,
};

Map<String, dynamic> _deviceVerdict(DeviceRun r, int stepsRequested) {
  final failed = r.steps.indexed.where((s) => !s.$2.ok).firstOrNull;
  return {
    'id': r.device,
    'passedSteps': r.steps.where((s) => s.ok).length,
    'totalSteps': stepsRequested,
    if (failed != null) 'failedStep': failed.$1 + 1,
    if (r.route != null) 'route': Redaction.text(r.route!),
    'errors': r.errors,
  };
}
