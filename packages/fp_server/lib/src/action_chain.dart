import 'package:mcp_dart/mcp_dart.dart';

import 'retired_tools.dart';

/// execute_action_chain: steps in the shape every tool that runs other tools
/// takes (run_on_devices, profile_action, a leak-check cycle).
typedef ChainStep = ({String tool, Map<String, dynamic> arguments});

/// The public schema of one composite step (task 02 §3): `tool` is required and
/// `arguments` is an object. Shared by every tool that runs other tools, so the
/// envelope reads the same everywhere and a nested call is coerced exactly as a
/// direct one (`_toolArgGates`) before [preflightChain] validates it.
///
/// Deliberately compact: the step tool's own argument constraints stay
/// authoritative in its registered schema, because copying every schema into
/// every composite would be an enormous union. Extra step fields are ignored by
/// [chainStep]; the `steps`/`cycle` description carries the tool list and an
/// example.
JsonSchema compositeStepSchema() => JsonSchema.object(
  properties: {'tool': JsonSchema.string(), 'arguments': JsonSchema.object()},
  required: ['tool'],
);

/// Reads `{"tool": ..., "arguments": {...}}`, or the shape the chain took
/// before (`{"action": "tap", "target": ...}`); null when it is neither.
ChainStep? chainStep(Object? raw) {
  if (raw is! Map) return null;
  final tool = raw['tool'];
  if (tool is String) {
    final arguments = raw['arguments'];
    if (arguments != null && arguments is! Map) return null;
    return (
      tool: tool,
      arguments: Map<String, dynamic>.from(arguments as Map? ?? const {}),
    );
  }
  final target = raw['target'] ?? raw['key'];
  return switch (raw['action']) {
    'tap' || 'tap_widget' => (tool: 'tap_widget', arguments: {'key': ?target}),
    'enter_text' || 'type' => (
      tool: 'enter_text',
      arguments: {'key': ?target, 'text': raw['text'] ?? ''},
    ),
    _ => null,
  };
}

/// [step] as an action of the SDK's own chain, which runs inside the app
/// without a round trip per step: a plain tap or text entry on a widget.
/// Null for anything it can't do (a gesture, waitFor, clearing a field).
Map<String, String>? inAppChainAction(ChainStep step) {
  final arguments = step.arguments;
  final key = (arguments['key'] ?? arguments['target'])?.toString();
  if (key == null || key.isEmpty) return null;
  final others = arguments.keys.toSet()..removeAll(const ['key', 'target']);
  final text = arguments['text'];
  return switch (step.tool) {
    'tap_widget' when others.isEmpty => {'action': 'tap', 'target': key},
    'enter_text' when others.length == 1 && text is String && text.isNotEmpty =>
      {'action': 'enter_text', 'target': key, 'text': text},
    _ => null,
  };
}

/// What a chain run one tool at a time did: each step's first line, and in
/// full the last one — the screen it left, or why it failed. [outcomes] has
/// one response per step that ran.
String describeChain(
  List<String> tools,
  List<String> outcomes, {
  required bool failed,
}) {
  final ran = outcomes.length;
  final done = failed ? ran - 1 : ran;
  final buffer = StringBuffer(
    failed
        ? 'Action chain stopped after $done/${tools.length} steps.'
        : 'Action chain: $done/${tools.length} steps done.',
  );
  for (var i = 0; i < ran; i++) {
    final last = i == ran - 1;
    final text = last
        ? outcomes[i].trim()
        : outcomes[i].trim().split('\n').first;
    buffer.write(
      '\nStep ${i + 1} ${tools[i]}${last && failed ? ' failed' : ''}: $text',
    );
  }
  // Only after a failure: the steps behind it never ran.
  if (ran < tools.length) {
    buffer.write('\nNot run: ${tools.sublist(ran).join(', ')}.');
  }
  return buffer.toString();
}

/// A composite's steps, validated before any of them run.
class ChainPreflight {
  const ChainPreflight.ready(this.steps) : problem = null, problemStep = null;
  const ChainPreflight.invalid(this.problem, this.problemStep)
    : steps = const [];

  /// Canonical steps: retired names translated and each step's arguments
  /// brought to its tool's schema types. Empty when [problem] is not null.
  final List<ChainStep> steps;

  /// A refusal that names the offending path (`steps[2].arguments`), or null
  /// when [steps] may run.
  final String? problem;

  /// The 1-based index of the offending step, when [problem] is not null.
  final int? problemStep;

  bool get ok => problem == null;
}

/// The tool names a composite can run, sorted, for a refusal's "Tools:" line.
String listedTools(
  Set<String> allowedTools,
  bool Function(String tool) isAvailable,
) => (allowedTools.where(isAvailable).toList()..sort()).join(', ');

/// Validates one nested call the way the server validates a direct call:
/// retired-name translation, the composite's allowed tool family,
/// availability, the active profile / capability, and the tool's own argument
/// gate (its registered schema). Returns the canonical step, or a refusal that
/// names [path] — never both.
///
/// Shared by [preflightChain] and a single-target composite (profile_action),
/// so every nested path validates identically. [what] names the composite
/// ("run in a chain", "be profiled").
({ChainStep? step, String? problem}) preflightStep(
  String tool,
  Map<String, dynamic> arguments, {
  required Set<String> allowedTools,
  required bool Function(String tool) isAvailable,
  required String? Function(String tool) profileRefusal,
  required ({Map<String, dynamic> args, String? problem}) Function(
    String tool,
    Map<String, dynamic> args,
  )
  gate,
  required String path,
  String what = "run in a chain",
}) {
  final translated = translateRetiredStep(tool, arguments);
  final listed = listedTools(allowedTools, isAvailable);
  if (!allowedTools.contains(translated.tool) ||
      !isAvailable(translated.tool)) {
    return (
      step: null,
      problem: '$path: "${translated.tool}" can\'t $what. Tools: $listed.',
    );
  }
  final refusal = profileRefusal(translated.tool);
  if (refusal != null) return (step: null, problem: '$path: $refusal');
  final (args: coerced, problem: problem) = gate(
    translated.tool,
    translated.arguments,
  );
  if (problem != null) {
    return (step: null, problem: '$path.arguments: $problem');
  }
  return (step: (tool: translated.tool, arguments: coerced), problem: null);
}

/// Validates every step of a composite before any of them runs: shape,
/// retired-step translation, the allowed tool family, availability, profile /
/// capability, and the step's own arguments (its nested contract). A malformed
/// step N means **zero** executed steps on every device — never "steps 1..N-1
/// ran, then a refusal".
///
/// [gate] is the per-tool argument check the server already applies to a
/// direct call (`_toolArgGates`), so a nested call and a direct call validate
/// identically. The returned steps carry the coerced arguments, so the caller
/// (and the in-app fast path) acts on canonical input only. [field] names the
/// argument in a refusal (`steps[2]` or `cycle[2]`).
ChainPreflight preflightChain(
  Object? rawSteps, {
  required Set<String> allowedTools,
  required bool Function(String tool) isAvailable,
  required String? Function(String tool) profileRefusal,
  required ({Map<String, dynamic> args, String? problem}) Function(
    String tool,
    Map<String, dynamic> args,
  )
  gate,
  String what = "run in a chain",
  String field = 'steps',
  String emptyProblem = 'steps is empty.',
}) {
  final raw = rawSteps is List ? rawSteps : const [];
  final steps = <ChainStep>[];
  for (var i = 0; i < raw.length; i++) {
    final shape = chainStep(raw[i]);
    if (shape == null) {
      return ChainPreflight.invalid(
        '$field[$i]: not a {"tool": ..., "arguments": {...}} step. '
        'Tools: ${listedTools(allowedTools, isAvailable)}.',
        i + 1,
      );
    }
    final result = preflightStep(
      shape.tool,
      shape.arguments,
      allowedTools: allowedTools,
      isAvailable: isAvailable,
      profileRefusal: profileRefusal,
      gate: gate,
      path: '$field[$i]',
      what: what,
    );
    if (result.problem != null) {
      return ChainPreflight.invalid(result.problem!, i + 1);
    }
    steps.add(result.step!);
  }
  if (steps.isEmpty) return ChainPreflight.invalid(emptyProblem, null);
  return ChainPreflight.ready(steps);
}
