/// Machine-readable twins of the verdict tools' text results (MCP
/// `structuredContent`): `assert_widget`, `wait_for`, `verify_feature` and
/// `run_on_devices`, plus the action/diagnostic tools (task 18): `get_errors`,
/// `get_app_summary`, `execute_action_chain` and `fill_form`, and the two
/// pilots of task 07: `audit_screen_health` and `navigate_to`.
///
/// A program (CI, `flutterpilot smoke`, `run_on_devices`' own comparison, a
/// reviewer script) reads `{"passed": false, ...}` instead of parsing prose.
/// The text content is unchanged — models read that — and no `outputSchema` is
/// declared: these schemas would add bytes to every session's `tools/list`
/// for shapes that are small and documented in `TOOLS.generated.md`. Without a
/// declared schema mcp_dart does not validate, so [structuredContracts] is an
/// executable, developer-side contract for the same shapes and the tests run
/// every fixture (and every builder's output) through
/// [structuredProblems]. [structuredShapes] is rendered from those contracts,
/// so the human-readable doc cannot drift from them.
///
/// A structured result always carries its verdict, even when the call failed
/// (`assert_widget` failing is `{passed: false, ...}`, not nothing): a caller
/// deciding what to do next reads it either way. When the verdict could not be
/// evaluated (no app, an extension error, a refusal before anything ran) the
/// result says so in an explicit `status`; the verdict fields are then defaults
/// and a consumer that only reads them would mistake "not evaluated" for a
/// clean answer. `status` values are per family and documented on each builder.
library;

import 'package:mcp_dart/mcp_dart.dart';

import 'fleet_compare.dart';
import 'redaction.dart';
import 'verification.dart';

// ---------------------------------------------------------------------------
// Executable developer-side contracts
// ---------------------------------------------------------------------------

/// One field of a structured family: its [spec] and whether it is always
/// present ([required]).
class StructuredField {
  const StructuredField(this.spec, {this.required = false});

  final StructuredSpec spec;
  final bool required;
}

/// A node of an executable structured contract (task 07): the small,
/// supported subset of JSON Schema the fixtures are checked against.
///
/// This is developer-side only. Nothing here is registered as an MCP
/// `outputSchema`, so it cannot grow `tools/list`; the tests run every fixture
/// and every real builder result through [problems], and [describe] renders the
/// human-readable shape that goes into `TOOLS.generated.md`.
abstract class StructuredSpec {
  const StructuredSpec();

  /// An object with [fields]; an unknown key is a problem.
  static StructuredSpec object(Map<String, StructuredField> fields) =>
      _ObjectSpec(fields);

  /// A list whose items all share [items].
  static StructuredSpec list(StructuredSpec items) => _ListSpec(items);

  static StructuredSpec boolean() => const _ScalarSpec(_ScalarKind.boolean);
  static StructuredSpec integer() => const _ScalarSpec(_ScalarKind.integer);
  static StructuredSpec number() => const _ScalarSpec(_ScalarKind.number);

  /// A string, closed to [oneOf] when it is given.
  static StructuredSpec string({Set<String>? oneOf}) =>
      _ScalarSpec(_ScalarKind.string, oneOf: oneOf);

  /// Every way [value] does not match this contract, each prefixed with its
  /// [path] into the payload; empty when it matches.
  List<String> problems(Object? value, [String path = '']);

  /// The human-readable shape, e.g. `{met: bool, route?: string}`.
  String describe();

  /// This contract as JSON Schema 2020-12, for an MCP `outputSchema`.
  ///
  /// Rendered from the same node [problems] checks, so a public schema cannot
  /// say something the developer-side validator does not: a closed string enum
  /// becomes `enum`, `required` lists exactly the required fields, and an
  /// object rejects unknown keys (`additionalProperties: false`) as [problems]
  /// does. Rendered on demand — nothing here reaches `tools/list` unless a
  /// caller advertises it (see `advertiseOutputSchemas`).
  Map<String, dynamic> toJsonSchema();
}

class _ObjectSpec extends StructuredSpec {
  _ObjectSpec(this.fields);

  final Map<String, StructuredField> fields;

  @override
  List<String> problems(Object? value, [String path = '']) {
    if (value is! Map) {
      return ['$path: expected an object, got ${_typeName(value)}'];
    }
    final out = <String>[];
    for (final MapEntry(key: name, value: field) in fields.entries) {
      if (!value.containsKey(name)) {
        if (field.required) out.add('$path.$name: missing');
        continue;
      }
      out.addAll(field.spec.problems(value[name], '$path.$name'));
    }
    for (final key in value.keys) {
      if (!fields.containsKey(key)) out.add('$path.$key: unexpected field');
    }
    return out;
  }

  @override
  String describe() =>
      '{${fields.entries.map((e) => '${e.key}${e.value.required ? '' : '?'}: ${e.value.spec.describe()}').join(', ')}}';

  @override
  Map<String, dynamic> toJsonSchema() => {
    'type': 'object',
    'properties': {
      for (final MapEntry(key: name, value: field) in fields.entries)
        name: field.spec.toJsonSchema(),
    },
    if (fields.values.any((f) => f.required))
      'required': [
        for (final MapEntry(key: name, value: field) in fields.entries)
          if (field.required) name,
      ],
    'additionalProperties': false,
  };
}

class _ListSpec extends StructuredSpec {
  _ListSpec(this.items);

  final StructuredSpec items;

  @override
  List<String> problems(Object? value, [String path = '']) {
    if (value is! List) {
      return ['$path: expected a list, got ${_typeName(value)}'];
    }
    return [
      for (var i = 0; i < value.length; i++)
        ...items.problems(value[i], '$path[$i]'),
    ];
  }

  @override
  String describe() => '[${items.describe()}]';

  @override
  Map<String, dynamic> toJsonSchema() => {
    'type': 'array',
    'items': items.toJsonSchema(),
  };
}

enum _ScalarKind { boolean, integer, number, string }

class _ScalarSpec extends StructuredSpec {
  const _ScalarSpec(this.kind, {this.oneOf});

  final _ScalarKind kind;
  final Set<String>? oneOf;

  @override
  List<String> problems(Object? value, [String path = '']) {
    switch (kind) {
      case _ScalarKind.boolean:
        if (value is! bool) {
          return ['$path: expected a bool, got ${_typeName(value)}'];
        }
      case _ScalarKind.integer:
        if (value is! int) {
          return ['$path: expected an int, got ${_typeName(value)}'];
        }
      case _ScalarKind.number:
        if (value is! num) {
          return ['$path: expected a number, got ${_typeName(value)}'];
        }
      case _ScalarKind.string:
        if (value is! String) {
          return ['$path: expected a string, got ${_typeName(value)}'];
        }
        if (oneOf != null && !oneOf!.contains(value)) {
          return ['$path: "$value" is not one of ${oneOf!.join(', ')}'];
        }
    }
    return const [];
  }

  @override
  String describe() => switch (kind) {
    _ScalarKind.boolean => 'bool',
    _ScalarKind.integer => 'int',
    _ScalarKind.number => 'num',
    _ScalarKind.string when oneOf != null =>
      oneOf!.map((v) => '"$v"').join('|'),
    _ScalarKind.string => 'string',
  };

  @override
  Map<String, dynamic> toJsonSchema() => {
    'type': switch (kind) {
      _ScalarKind.boolean => 'boolean',
      _ScalarKind.integer => 'integer',
      _ScalarKind.number => 'number',
      _ScalarKind.string => 'string',
    },
    // Sorted so the rendered schema is deterministic across runs.
    if (oneOf != null) 'enum': oneOf!.toList()..sort(),
  };
}

String _typeName(Object? value) =>
    value == null ? 'null' : value.runtimeType.toString();

// --- the eight original families plus the two task-07 pilots ---------------

StructuredField _req(StructuredSpec spec) =>
    StructuredField(spec, required: true);
StructuredField _opt(StructuredSpec spec) => StructuredField(spec);

final StructuredSpec _notVerified = StructuredSpec.string(
  oneOf: {'passed', 'failed', 'not_verified'},
);
final StructuredSpec _errorSpec = StructuredSpec.object({
  'kind': _req(StructuredSpec.string(oneOf: {'exception', 'overflow'})),
  'message': _req(StructuredSpec.string()),
  'location': _opt(StructuredSpec.string()),
  'beforeReload': _req(StructuredSpec.boolean()),
});

/// The executable contract for every structured family, keyed by tool name.
/// `structuredShapes` and the tests both read this, so a builder and its
/// documented shape cannot drift apart.
final structuredContracts = <String, StructuredSpec>{
  'assert_widget': StructuredSpec.object({
    'passed': _req(StructuredSpec.boolean()),
    'check': _req(
      StructuredSpec.string(
        oneOf: {'text', 'key', 'enabled', 'disabled', 'count', 'none'},
      ),
    ),
    'expected': _opt(StructuredSpec.string()),
    'found': _opt(StructuredSpec.integer()),
    'reason': _opt(StructuredSpec.string()),
  }),
  'wait_for': StructuredSpec.object({
    'met': _req(StructuredSpec.boolean()),
    'waitedMs': _req(StructuredSpec.integer()),
    'timedOut': _req(StructuredSpec.boolean()),
    'condition': _req(
      StructuredSpec.string(
        oneOf: {'key', 'route', 'state', 'frames', 'animations', 'none'},
      ),
    ),
    'route': _opt(StructuredSpec.string()),
    // Set only when the wait could not be evaluated (no app, a refusal).
    'status': _opt(
      StructuredSpec.string(oneOf: {'ok', 'unavailable', 'refused'}),
    ),
  }),
  'verify_feature': StructuredSpec.object({
    'feature': _opt(StructuredSpec.string()),
    'criteria': _req(
      StructuredSpec.list(
        StructuredSpec.object({
          'index': _req(StructuredSpec.integer()),
          'text': _req(StructuredSpec.string()),
          'verdict': _req(_notVerified),
          'warnings': _req(StructuredSpec.integer()),
        }),
      ),
    ),
    'report': _opt(StructuredSpec.string()),
    'status': _opt(
      StructuredSpec.string(oneOf: {'ok', 'refused', 'unavailable'}),
    ),
    'reason': _opt(StructuredSpec.string()),
  }),
  'run_on_devices': StructuredSpec.object({
    'devices': _req(
      StructuredSpec.list(
        StructuredSpec.object({
          'id': _req(StructuredSpec.string()),
          'passedSteps': _req(StructuredSpec.integer()),
          'totalSteps': _req(StructuredSpec.integer()),
          'failedStep': _opt(StructuredSpec.integer()),
          'route': _opt(StructuredSpec.string()),
          'errors': _req(StructuredSpec.integer()),
          'reached': _req(StructuredSpec.boolean()),
        }),
      ),
    ),
    'same': _req(StructuredSpec.boolean()),
    'status': _opt(StructuredSpec.string(oneOf: {'ok', 'partial', 'refused'})),
    'reason': _opt(StructuredSpec.string()),
  }),
  'get_errors': StructuredSpec.object({
    'hasErrors': _req(StructuredSpec.boolean()),
    'count': _req(StructuredSpec.integer()),
    'errors': _req(StructuredSpec.list(_errorSpec)),
    'status': _opt(StructuredSpec.string(oneOf: {'ok', 'unavailable'})),
    'reason': _opt(StructuredSpec.string()),
  }),
  'get_app_summary': StructuredSpec.object({
    'connected': _req(StructuredSpec.boolean()),
    'device': _opt(StructuredSpec.string()),
    'platform': _opt(StructuredSpec.string()),
    'route': _opt(StructuredSpec.string()),
    'errorCount': _req(StructuredSpec.integer()),
    'buildMode': _opt(StructuredSpec.string()),
  }),
  'execute_action_chain': StructuredSpec.object({
    'passed': _req(StructuredSpec.boolean()),
    'completedSteps': _req(StructuredSpec.integer()),
    'totalSteps': _req(StructuredSpec.integer()),
    'failedStep': _opt(StructuredSpec.integer()),
    'failureReason': _opt(StructuredSpec.string()),
    'status': _opt(
      StructuredSpec.string(oneOf: {'ok', 'refused', 'unavailable'}),
    ),
  }),
  'fill_form': StructuredSpec.object({
    'submitted': _req(StructuredSpec.boolean()),
    'filledCount': _req(StructuredSpec.integer()),
    'totalFields': _req(StructuredSpec.integer()),
    'failedField': _opt(StructuredSpec.string()),
    'status': _opt(StructuredSpec.string(oneOf: {'ok', 'unavailable'})),
  }),
  'audit_screen_health': StructuredSpec.object({
    'requested': _req(StructuredSpec.integer()),
    'visited': _req(StructuredSpec.integer()),
    'audited': _req(StructuredSpec.integer()),
    'failed': _req(StructuredSpec.integer()),
    'skipped': _req(StructuredSpec.integer()),
    'findings': _req(
      StructuredSpec.object({
        'overflows': _req(StructuredSpec.integer()),
        'tapTargets': _req(StructuredSpec.integer()),
        'unlabeled': _req(StructuredSpec.integer()),
        'lowContrast': _req(StructuredSpec.integer()),
        'readingOrderJumps': _req(StructuredSpec.integer()),
      }),
    ),
    'restored': _req(StructuredSpec.boolean()),
    'incomplete': _req(StructuredSpec.boolean()),
    'loading': _req(StructuredSpec.boolean()),
    'status': _opt(
      StructuredSpec.string(oneOf: {'ok', 'partial', 'unavailable'}),
    ),
    'reason': _opt(StructuredSpec.string()),
  }),
  'navigate_to': StructuredSpec.object({
    'requested': _req(StructuredSpec.string()),
    'current': _opt(StructuredSpec.string()),
    'waitRequired': _req(StructuredSpec.boolean()),
    'waitStatus': _opt(StructuredSpec.string(oneOf: {'found', 'missing'})),
    'completed': _req(StructuredSpec.boolean()),
    'uncertain': _req(StructuredSpec.boolean()),
    'status': _opt(
      StructuredSpec.string(oneOf: {'ok', 'refused', 'unavailable'}),
    ),
  }),
};

/// A short note appended to a family's shape in `TOOLS.generated.md`.
const _shapeNotes = <String, String>{'verify_feature': 'finish, or a refusal'};

/// Every tool that returns a structured result, and its shape, read by
/// `tool/generate_tools_doc.dart` into `TOOLS.generated.md`. Rendered from
/// [structuredContracts] (task 07), so it is the contract's human-readable
/// twin rather than a second, hand-maintained copy.
final structuredShapes = <String, String>{
  for (final MapEntry(key: name, value: spec) in structuredContracts.entries)
    name:
        '${spec.describe()}${_shapeNotes[name] == null ? '' : ' (${_shapeNotes[name]})'}',
};

/// The pilot families whose contract may be advertised as an MCP
/// `outputSchema` (task 07 §11: one or two small, stable families).
///
/// Both are task-07 pilots whose every documented verdict path — including the
/// no-app `status: "unavailable"` path — is already proven to return
/// contract-valid structured content by `structured_results_test`. Nothing
/// else is advertised.
const outputSchemaPilotFamilies = {'audit_screen_health', 'navigate_to'};

/// Each pilot family's MCP `outputSchema`, rendered from [structuredContracts]
/// so the wire schema and the developer-side validator cannot drift apart.
///
/// Only read when `advertiseOutputSchemas` is on (off by default): advertising
/// a schema commits every *non-error* result of that tool to matching it at the
/// protocol layer and grows the client `tools/list` (measured: 822 B +
/// 402 B = 1,256 B; the model-facing projection the budgets measure does not
/// move). Decision and measurements: `docs/tasks/mcp-quality-next/PROGRESS.md`
/// (task 07 §11–12).
final structuredOutputSchemas = <String, Map<String, dynamic>>{
  for (final name in outputSchemaPilotFamilies)
    if (structuredContracts[name] case final contract?)
      name: contract.toJsonSchema(),
};

/// Every way [structured] does not match the contract for the tool [name],
/// each prefixed with the tool name; empty when it matches.
///
/// Developer-side validation: the tests run every variant fixture and every
/// builder's output through this. It is deliberately not an MCP
/// `outputSchema`, so nothing validates at the protocol layer and
/// `tools/list` does not grow.
List<String> structuredProblems(String name, Map<String, dynamic> structured) {
  final spec = structuredContracts[name];
  if (spec == null) return ['$name: no contract'];
  return [for (final problem in spec.problems(structured)) '$name$problem'];
}

// ---------------------------------------------------------------------------
// Result plumbing
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// The families
// ---------------------------------------------------------------------------

/// `assert_widget`'s structured result: what was checked, whether it held, and
/// what the check saw.
///
/// `found` is the number the check saw — 1 for a text, key or enabled check
/// that passed, the widget count for a count check — and is left out when the
/// check failed: the extension answers a failed assertion with its message,
/// not with a count, and the server does not read the count back out of the
/// message. `reason` is that message. A call with nothing to check is
/// `check: "none"`, `passed: false` and the advice as `reason`: a refusal, not
/// a failed assertion.
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
///
/// [status] is `"unavailable"` when the wait could not be evaluated at all
/// (the app did not answer); `met`/`timedOut` are then defaults, not
/// observations. A genuine timeout stays `status`-less (its own `timedOut` is
/// the truth): "the condition did not hold in time" is an evaluated verdict,
/// "there was no app to ask" is not.
Map<String, dynamic> waitForVerdict({
  required String condition,
  required bool met,
  required int waitedMs,
  required int timeoutMs,
  bool? timedOut,
  String? status,
}) => {
  'met': met,
  'waitedMs': waitedMs,
  'timedOut': timedOut ?? (!met && timeoutMs > 0 && waitedMs >= timeoutMs),
  'condition': condition,
  'status': ?status,
};

/// `verify_feature(finish: true)`'s text and structured result.
///
/// The other `verify_feature` calls (start, picking a criterion, a status read)
/// are not verdicts and carry no structured content; a refusal does, with an
/// empty `criteria` list and `status: "refused"` (see
/// `verification_tools.dart`).
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
/// route it ended on. `reached` is false for a device that could not be
/// reached at all (its reason stays in the text), so 0 of N is never read as a
/// device that ran everything and passed nothing. `status` is `"partial"` when
/// at least one device was unreachable (the sweep ran, but not on every
/// device) and `"refused"` when the plan or the device list was rejected
/// before anything ran (then `devices` is empty); it is absent on a full run.
Map<String, dynamic> fleetVerdict(
  List<DeviceRun> runs, {
  required int stepsRequested,
  required bool same,
  String? status,
  String? reason,
}) => {
  'devices': [for (final r in runs) _deviceVerdict(r, stepsRequested)],
  'same': same,
  'status': ?status,
  'reason': ?reason,
};

/// The structured result of a `run_on_devices` call refused before any device
/// acted (an invalid plan or an unknown device list): nothing ran anywhere.
/// [status] `"refused"` is distinct from the `"partial"` of a sweep that ran on
/// some devices and not others.
Map<String, dynamic> fleetRefusalVerdict(String reason) => {
  'devices': <Map<String, dynamic>>[],
  'same': false,
  'status': 'refused',
  'reason': Redaction.text(reason),
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
    'reached': r.unreachable == null,
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
///
/// [status] is `"unavailable"` when the app did not answer and the list could
/// not be read; `hasErrors`/`count`/`errors` are then defaults, not a clean
/// app. [reason] carries the extension's message.
Map<String, dynamic> errorsVerdict({
  required List<Map<String, dynamic>> since,
  required List<Map<String, dynamic>> before,
  String? status,
  String? reason,
}) {
  final errors = [
    for (final e in since) _structuredError(e, beforeReload: false),
    for (final e in before) _structuredError(e, beforeReload: true),
  ];
  return {
    'hasErrors': errors.isNotEmpty,
    'count': errors.length,
    'errors': errors,
    'status': ?status,
    if (reason != null) 'reason': Redaction.text(reason),
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
///
/// [status] is `"refused"` when the plan was rejected before any step ran (so
/// `completedSteps` is 0 and `failedStep` names the offending step), and
/// `"unavailable"` when the app did not carry the chain out; it is absent on a
/// normal run.
Map<String, dynamic> actionChainVerdict({
  required bool passed,
  required int completedSteps,
  required int totalSteps,
  int? failedStep,
  String? failureReason,
  String? status,
}) => {
  'passed': passed,
  'completedSteps': completedSteps,
  'totalSteps': totalSteps,
  'failedStep': ?failedStep,
  'failureReason': ?failureReason,
  'status': ?status,
};

/// `fill_form`'s structured result: how many fields were filled, the total,
/// whether submit was tapped, and the first field that could not be filled.
///
/// [status] is `"unavailable"` when the app did not answer; the counts are
/// then defaults, not a fill that did nothing.
Map<String, dynamic> fillFormVerdict({
  required bool submitted,
  required int filledCount,
  required int totalFields,
  String? failedField,
  String? status,
}) => {
  'submitted': submitted,
  'filledCount': filledCount,
  'totalFields': totalFields,
  'failedField': ?failedField,
  'status': ?status,
};

/// `audit_screen_health`'s structured result: how much of the requested sweep
/// actually ran and what it found, per category.
///
/// One screen (no `routes`) is `requested: 0`, `visited: 0`, `audited: 1`;
/// a sweep is the routes asked for and the ones reached and audited. `failed`
/// counts a route that could not be reached or audited, `skipped` the routes
/// past the per-call cap, and `incomplete` is true when anything was skipped,
/// failed or left a screen still loading — so `status: "ok"` means the sweep
/// covered exactly what it was asked to. `restored` says the sweep ended where
/// it started (or never left). [status] is `"unavailable"` when even the
/// current screen could not be read.
Map<String, dynamic> auditVerdict({
  required int requested,
  required int visited,
  required int audited,
  required int failed,
  required int skipped,
  required Map<String, int> findings,
  required bool restored,
  required bool incomplete,
  required bool loading,
  String? status,
  String? reason,
}) => {
  'requested': requested,
  'visited': visited,
  'audited': audited,
  'failed': failed,
  'skipped': skipped,
  'findings': {
    'overflows': findings['overflows'] ?? 0,
    'tapTargets': findings['tapTargets'] ?? 0,
    'unlabeled': findings['unlabeled'] ?? 0,
    'lowContrast': findings['lowContrast'] ?? 0,
    'readingOrderJumps': findings['readingOrderJumps'] ?? 0,
  },
  'restored': restored,
  'incomplete': incomplete,
  'loading': loading,
  'status': ?status,
  if (reason != null) 'reason': Redaction.text(reason),
};

/// `navigate_to`'s compact structured result (task 07 pilot): the route asked
/// for, the route the app reports it is on, whether a `waitFor` was required
/// and how it went, and whether the navigation is confirmed.
///
/// `uncertain` is true when the app's stack could not be read after the
/// navigation: the call answered, but the route it lands on is not confirmed,
/// and a caller should not treat `completed` as proof the page is showing.
/// [status] is `"unavailable"` when the navigation itself did not reach the
/// app; it is absent on a normal navigation.
Map<String, dynamic> navigationVerdict({
  required String requested,
  String? current,
  required bool waitRequired,
  String? waitStatus,
  required bool completed,
  bool uncertain = false,
  String? status,
}) => {
  'requested': Redaction.text(requested),
  'current': ?(current == null ? null : Redaction.text(current)),
  'waitRequired': waitRequired,
  'waitStatus': ?waitStatus,
  'completed': completed,
  'uncertain': uncertain,
  'status': ?status,
};
