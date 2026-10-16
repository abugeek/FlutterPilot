// The policy wrapper between the model and the MCP session (task 04 §6–§7).
//
// The runner needs `--allow-destructive` to reset the app before each case —
// loading a scenario replaces stored data and mocks. The model must not inherit
// that. Every model call goes through [PolicyClient], which refuses the
// destructive tools outright and refuses a composite whose *nested* step would
// call one, so the setup session's stronger permissions never leak into what is
// being measured.
//
// The deny set is derived from the server's own reviewed effects
// (`toolEffects`), not a second list that can drift: a tool the server marks
// destructive is exactly a tool the model may not call.
library;

import 'package:fp_server/src/action_chain.dart';
import 'package:fp_server/src/tool_annotations.dart';

import 'mcp_session.dart';

/// The tools the model may not call, derived from the server's reviewed
/// effects. Sorted for deterministic messages.
final Set<String> destructiveToolNames = {
  for (final entry in toolEffects.entries)
    if (entry.value == ToolEffect.destructive) entry.key,
};

/// The composites whose arguments name other tools that must be checked too.
const _compositeTools = {
  'execute_action_chain',
  'run_on_devices',
  'profile_action',
};

/// Wraps a session so the model can use everything except [denied], including
/// a denied tool named by a composite's nested step. Refusals come back as a
/// normal tool error, so the model sees why and the run is still scored.
class PolicyClient implements McpClient {
  PolicyClient(this._inner, {Set<String>? denied})
    : denied = denied ?? destructiveToolNames;

  final McpClient _inner;

  /// Tool names the model may not call.
  final Set<String> denied;

  /// The names refused, for the report's policy record.
  List<String> get deniedList => denied.toList()..sort();

  @override
  String get instructions => _inner.instructions;

  @override
  List<McpTool> get tools => _inner.tools;

  @override
  Stream<List<McpTool>> get toolListChanges => _inner.toolListChanges;

  @override
  Future<McpCallResult> call(String name, [Map<String, dynamic>? arguments]) {
    final refusal = refusalFor(name, arguments ?? const <String, dynamic>{});
    if (refusal != null) {
      return Future.value(
        McpCallResult(
          [
            {'type': 'text', 'text': refusal},
          ],
          true,
          0,
          refusal.length,
        ),
      );
    }
    return _inner.call(name, arguments);
  }

  /// The reason [name] may not be called with [arguments], or null when it may.
  String? refusalFor(String name, Map<String, dynamic> arguments) {
    if (denied.contains(name)) {
      return 'Refused: "$name" changes or deletes stored data and is reserved '
          'for fixture setup; the model may not call it.';
    }
    if (!_compositeTools.contains(name)) return null;
    for (final step in _nestedSteps(arguments)) {
      if (denied.contains(step.tool)) {
        return 'Refused: "$name" runs "${step.tool}", which changes or '
            'deletes stored data and is reserved for fixture setup; the model '
            'may not call it.';
      }
    }
    return null;
  }

  /// Every nested call [arguments] names: a top-level `{tool, arguments}`
  /// (profile_action) and each `steps`/`cycle` entry (the chain composites).
  /// Unrecognised steps are ignored here; the server's own preflight validates
  /// their shape.
  Iterable<ChainStep> _nestedSteps(Map<String, dynamic> arguments) sync* {
    final single = chainStep(arguments);
    if (single != null) yield single;
    for (final key in const ['steps', 'cycle']) {
      final raw = arguments[key];
      if (raw is! List) continue;
      for (final entry in raw) {
        final step = chainStep(entry);
        if (step != null) yield step;
      }
    }
  }
}

/// Tools the model may call in a read-only evaluation (task 05 §4): the
/// server's own `reads` effect, plus the *observing* mode of the few tools whose
/// other mode mutates or drives the app.
///
/// The allow-list is derived from the reviewed effects, not a second list that
/// can drift: a tool the server marks `acts` or `destructive` is refused unless
/// it is named here as an observing tool, and even then only for its
/// non-mutating arguments ([readOnlyRefusalFor]).
final Set<String> readOnlyToolNames = {
  for (final entry in toolEffects.entries)
    if (entry.value == ToolEffect.reads) entry.key,
  // Advertised `acts` because one mode mutates; the other observes.
  'get_state',
  'get_debug_logs',
  'get_http_profile',
  'audit_screen_health',
};

/// The argument of a read-only tool that turns the call into a mutation: the
/// diagnostic clears (FlutterPilot's own capture) and `audit_screen_health`'s
/// route sweep, which navigates away and back.
const _mutatingArguments = <String, String>{
  'get_state': 'clear',
  'get_debug_logs': 'clear',
  'get_http_profile': 'clear',
  'audit_screen_health': 'routes',
};

/// Whether [name] with [arguments] is a read the inspection model may make.
bool isReadOnlyCall(String name, Map<String, dynamic> arguments) =>
    readOnlyRefusalFor(name, arguments) == null;

/// Why the model may not call [name] with [arguments] in a read-only suite, or
/// null when the call only observes the app.
///
/// Argument-aware (task 01 §3): a *clear* empties FlutterPilot's capture and a
/// route *sweep* navigates, so neither is a read even though a plain
/// `get_state`/`audit_screen_health` is. A composite tool is refused outright
/// and, when it names nested steps, the first offending step is named — a
/// mutating call can never hide behind a wrapper (task 05 §4–§5).
String? readOnlyRefusalFor(String name, Map<String, dynamic> arguments) {
  final mutating = _mutatingArguments[name];
  if (mutating != null && _mutatesThrough(name, mutating, arguments)) {
    return 'Refused: "$name" with "$mutating" is not a read (it changes what '
        'FlutterPilot captured or drives the app); the read-only suite only '
        'observes.';
  }
  if (readOnlyToolNames.contains(name)) return null;
  if (_compositeTools.contains(name)) {
    for (final step in _nestedStepsOf(arguments)) {
      final nested = readOnlyRefusalFor(step.tool, step.arguments);
      if (nested != null) {
        return 'Refused: "$name" runs "${step.tool}", which the read-only '
            'suite may not use. $nested';
      }
    }
    return 'Refused: "$name" drives the app; the read-only suite only observes '
        'with single read tools.';
  }
  return 'Refused: "$name" is not a read-only tool; the read-only suite only '
      'observes the app.';
}

/// Whether [arguments] requests the mutating [mode] of [name].
bool _mutatesThrough(String name, String mode, Map<String, dynamic> arguments) {
  final value = arguments[mode];
  if (value == null) return false;
  if (mode == 'routes') {
    // A route sweep navigates; an empty/absent list does not.
    return value is List ? value.isNotEmpty : true;
  }
  return value == true || '$value'.toLowerCase() == 'true';
}

/// Every nested call [arguments] names (see [PolicyClient._nestedSteps]).
Iterable<ChainStep> _nestedStepsOf(Map<String, dynamic> arguments) sync* {
  final single = chainStep(arguments);
  if (single != null) yield single;
  for (final key in const ['steps', 'cycle']) {
    final raw = arguments[key];
    if (raw is! List) continue;
    for (final entry in raw) {
      final step = chainStep(entry);
      if (step != null) yield step;
    }
  }
}

/// Wraps a session so the inspection model may only make read-only calls
/// (task 05 §4). Unlike [PolicyClient], which denies only the destructive set,
/// this allows only reads: navigation, settings, mocks, clears, scenario
/// writes/loads, profiler actions, custom code and any driving call come back
/// as a normal tool error, so the run is scored and the refusal is visible.
class ReadOnlyPolicyClient implements McpClient {
  ReadOnlyPolicyClient(this._inner);

  final McpClient _inner;

  /// The names the model may call at all, for the report's policy record.
  List<String> get allowedList => readOnlyToolNames.toList()..sort();

  @override
  String get instructions => _inner.instructions;

  @override
  List<McpTool> get tools => _inner.tools;

  @override
  Stream<List<McpTool>> get toolListChanges => _inner.toolListChanges;

  @override
  Future<McpCallResult> call(String name, [Map<String, dynamic>? arguments]) {
    final refusal = readOnlyRefusalFor(
      name,
      arguments ?? const <String, dynamic>{},
    );
    if (refusal != null) {
      return Future.value(
        McpCallResult(
          [
            {'type': 'text', 'text': refusal},
          ],
          true,
          0,
          refusal.length,
        ),
      );
    }
    return _inner.call(name, arguments);
  }
}
