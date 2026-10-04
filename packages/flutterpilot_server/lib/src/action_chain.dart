/// execute_action_chain: steps in the shape every tool that runs other tools
/// takes (run_on_devices, profile_action, a leak-check cycle).
typedef ChainStep = ({String tool, Map<String, dynamic> arguments});

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
