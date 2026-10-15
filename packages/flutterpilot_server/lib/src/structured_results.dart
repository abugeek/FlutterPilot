/// Machine-readable twins of the verdict tools' text results (MCP
/// `structuredContent`): `assert_widget`, `wait_for`, `verify_feature` and
/// `run_on_devices`, plus the action/diagnostic tools (task 18): `get_errors`,
/// `get_app_summary`, `execute_action_chain` and `fill_form`.
///
/// A program (CI, `flutterpilot smoke`, `run_on_devices`' own comparison, a
/// reviewer script) reads `{"passed": false, ...}` instead of parsing prose.
/// The text content is unchanged — models read that — and no `outputSchema` is
/// declared: these schemas would add bytes to every session's `tools/list`
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
  'get_errors':
      '{hasErrors: bool, count: int, errors: [{kind: "exception"|"overflow", '
      'message: string, location?: string, beforeReload: bool}]}',
  'get_app_summary':
      '{connected: bool, device?: string, platform?: string, route?: string, '
      'errorCount: int, buildMode?: string}',
  'execute_action_chain':
      '{passed: bool, completedSteps: int, totalSteps: int, failedStep?: int, '
      'failureReason?: string}',
  'fill_form':
      '{submitted: bool, filledCount: int, totalFields: int, '
      'failedField?: string}',
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
/// reason (no app, a refusal) returns long before its deadline. [timedOut]
/// passes the app's own flag for the one wait whose answer carries it
/// (`ext.flutterpilot.waitForAnimation`'s `status`), so that branch does not
/// depend on the copied default timeout.
Map<String, dynamic> waitForVerdict({
  required String condition,
  required bool met,
  required int waitedMs,
  required int timeoutMs,
  bool? timedOut,
}) => {
  'met': met,
  'waitedMs': waitedMs,
  'timedOut': timedOut ?? (!met && timeoutMs > 0 && waitedMs >= timeoutMs),
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

/// The first `package:`/`file:` frame in a stack trace: the file location an
/// agent needs to fix the error. Shared by the errors resource and
/// [errorsVerdict].
String? firstStackLocation(String? stack) {
  if (stack == null || stack.isEmpty) return null;
  return RegExp(r'(?:package:|file:)[^\s)]+').firstMatch(stack)?.group(0);
}

/// `get_errors`' structured result: whether the app has uncaught errors, how
/// many, and each one's kind, message, source location and freshness.
///
/// [since] and [before] are the two lists the text already shows
/// (error_freshness.dart). Entries from before the last reload carry
/// `beforeReload: true`: the reload may already have fixed them, so a caller
/// asking "is the app healthy now?" filters them out. `count` is the number of
/// entries returned, `since` first; an empty list is a clean app.
Map<String, dynamic> errorsVerdict({
  required List<Map<String, dynamic>> since,
  required List<Map<String, dynamic>> before,
}) {
  final errors = [
    for (final e in since) _structuredError(e, beforeReload: false),
    for (final e in before) _structuredError(e, beforeReload: true),
  ];
  return {
    'hasErrors': errors.isNotEmpty,
    'count': errors.length,
    'errors': errors,
  };
}

Map<String, dynamic> _structuredError(
  Map<String, dynamic> error, {
  required bool beforeReload,
}) {
  final message = error['exception']?.toString() ?? 'Unknown error';
  return {
    'kind': _errorKind(message),
    'message': message,
    'location': ?firstStackLocation(error['stackTrace']?.toString()),
    'beforeReload': beforeReload,
  };
}

/// A layout overflow reaches `get_errors` as an exception whose message says
/// "overflowed"; everything else is an `exception`.
String _errorKind(String message) =>
    message.toLowerCase().contains('overflow') ? 'overflow' : 'exception';

/// `get_app_summary`'s structured result: the key runtime facts about the
/// connected app.
///
/// [connected] is false when nothing answered; the other fields are present
/// only when the app reported them. [errorCount] counts the uncaught errors
/// since the last reload — the same number the text headlines.
Map<String, dynamic> appSummaryVerdict({
  required bool connected,
  String? device,
  String? platform,
  String? route,
  int errorCount = 0,
  String? buildMode,
}) => {
  'connected': connected,
  'device': ?device,
  'platform': ?platform,
  'route': ?route,
  'errorCount': errorCount,
  'buildMode': ?buildMode,
};

/// `execute_action_chain`'s structured result: whether every step passed, how
/// many ran, the total, and — when one failed — which step (1-based) and why.
Map<String, dynamic> actionChainVerdict({
  required bool passed,
  required int completedSteps,
  required int totalSteps,
  int? failedStep,
  String? failureReason,
}) => {
  'passed': passed,
  'completedSteps': completedSteps,
  'totalSteps': totalSteps,
  'failedStep': ?failedStep,
  'failureReason': ?failureReason,
};

/// `fill_form`'s structured result: how many fields were filled, the total,
/// whether submit was tapped, and the first field that could not be filled.
Map<String, dynamic> fillFormVerdict({
  required bool submitted,
  required int filledCount,
  required int totalFields,
  String? failedField,
}) => {
  'submitted': submitted,
  'filledCount': filledCount,
  'totalFields': totalFields,
  'failedField': ?failedField,
};
