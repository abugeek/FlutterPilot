part of '../flutterpilot_server.dart';

/// The intro prompt, kept from before task 17 (id, title and description are
/// shared with [promptListJson] so the two cannot drift).
const _guidePromptName = 'flutterpilot_guide';
const _guidePromptTitle = 'FlutterPilot Usage Guide';
const _guidePromptDescription =
    'Complete guide on how to use FlutterPilot tools effectively. '
    'Call this prompt at the start of a session to understand all available '
    'tools, when to use each one, and recommended workflows.';
const _guidePromptResultDescription = 'FlutterPilot complete usage guide';

/// One curated workflow prompt (task 17): an intent-level sequence of tool
/// calls, so a fast model starts from the right order instead of guessing.
class _PromptSpec {
  const _PromptSpec({
    required this.name,
    required this.title,
    required this.description,
    required this.build,
    this.arguments = const {},
  });

  final String name;
  final String title;
  final String description;

  /// The prompt body, from the (optional) arguments the client passed.
  final String Function(Map<String, dynamic> args) build;

  /// The arguments `prompts/list` advertises and `prompts/get` validates.
  final Map<String, PromptArgumentDefinition> arguments;
}

/// A focus line for a prompt that takes an optional target; empty otherwise.
String _focusLine(String? value, String subject) =>
    value == null || value.isEmpty ? '' : '\n\nFocus on $subject.';

String _debugLayoutOverflowPrompt(Map<String, dynamic> args) {
  final key = args['widgetKey']?.toString();
  return 'Locate, analyze, and fix a RenderFlex layout overflow on screen.\n'
      '\n'
      'Workflow:\n'
      '1. Call `get_errors` to identify the overflow warning and the culprit '
      'widget (the RenderFlex whose children overflow).\n'
      '2. Call `inspect_widget(key: "...", layout: true)` on the culprit for '
      'each box\'s constraints and size, and why the Row/Column overflows by '
      'the amount reported.\n'
      '3. Open the Dart source file the error names and find the offending '
      'flex.\n'
      '4. Fix the flex constraint: wrap the child in `Expanded` or '
      '`Flexible`, or the column in a `SingleChildScrollView`.\n'
      '5. Call `hot_reload`, then call `get_errors` to confirm the overflow '
      'is gone.'
      '${_focusLine(key, 'the widget with key "$key"')}';
}

String _diagnoseExceptionPrompt(Map<String, dynamic> args) {
  final index = args['errorIndex']?.toString();
  return 'Diagnose and fix an unhandled exception or red screen.\n'
      '\n'
      'Workflow:\n'
      '1. Call `get_errors(report: true)` for the compact crash report: the '
      'exception, the top failing app frame (file:line), the culprit widget '
      'and the route.\n'
      '2. Call `get_debug_logs(sinceSeconds: 30)` to inspect the logs around '
      'the failure.\n'
      '3. Open the top app frame in the report and find the cause.\n'
      '4. Fix the issue in the Dart source.\n'
      '5. Call `hot_reload` and verify with `get_errors`; if the failure '
      'corrupted the app state, call `hot_reload(restart: true)` first.'
      '${_focusLine(index, 'error #$index from `get_errors`')}';
}

String _createIntegrationTestPrompt(Map<String, dynamic> args) {
  final name = args['name']?.toString() ?? 'feature_flow';
  return 'Record actions on the active screen and generate a runnable '
      'integration test.\n'
      '\n'
      'Workflow:\n'
      '1. Call `generate_test(start: true)` to hot restart the app and begin '
      'recording from a clean first screen.\n'
      '2. Drive the target flow with `tap_widget`, `enter_text`, `wait_for` '
      'and `assert_widget`; every step is recorded.\n'
      '3. Call `generate_test(name: "$name")` to write the test file and run '
      'it on the device.\n'
      '4. Confirm the result says the test passed, then read the generated '
      'test file.';
}

String _auditScreenHealthPrompt(Map<String, dynamic> args) {
  final route = args['route']?.toString();
  return 'Audit accessibility, contrast and layout health on the current '
      'screen.\n'
      '\n'
      'Workflow:\n'
      '1. Call `audit_screen_health()`. Pass a route (or several) to sweep '
      'specific screens.\n'
      '2. Review unlabeled tappable controls a screen reader cannot name, '
      'with the widget and file:line that adds each tap.\n'
      '3. Review the WCAG contrast findings (text below the measured '
      'threshold).\n'
      '4. Check the screen reader traversal order for jumps back up the '
      'screen.\n'
      '5. Fix the findings in Dart code (Semantics labels, colors, layout) '
      'and call `hot_reload`.'
      '${_focusLine(route, 'the route "$route"')}';
}

/// The four curated workflow prompts (task 17), in `prompts/list` order.
const _workflowPrompts = <_PromptSpec>[
  _PromptSpec(
    name: 'debug_layout_overflow',
    title: 'Debug Layout Overflow',
    description:
        'Locate, analyze, and fix a RenderFlex layout overflow on screen.',
    arguments: {
      'widgetKey': PromptArgumentDefinition(
        description: 'Key of the overflowing widget to focus on (optional).',
      ),
    },
    build: _debugLayoutOverflowPrompt,
  ),
  _PromptSpec(
    name: 'diagnose_exception',
    title: 'Diagnose Runtime Exception',
    description:
        'Step-by-step diagnostic loop for unhandled exceptions and red '
        'screens.',
    arguments: {
      'errorIndex': PromptArgumentDefinition(
        description:
            'Index of the error in `get_errors` to focus on '
            '(optional).',
      ),
    },
    build: _diagnoseExceptionPrompt,
  ),
  _PromptSpec(
    name: 'create_integration_test',
    title: 'Create Integration Test',
    description:
        'Record actions on the active screen and generate a runnable '
        'integration test.',
    arguments: {
      'name': PromptArgumentDefinition(
        description: 'File name for the generated test (optional).',
      ),
    },
    build: _createIntegrationTestPrompt,
  ),
  _PromptSpec(
    name: 'audit_screen_health',
    title: 'Audit Screen Health',
    description:
        'Audit accessibility, contrast, and layout health on the current '
        'screen.',
    arguments: {
      'route': PromptArgumentDefinition(
        description: 'Route to audit instead of the current screen (optional).',
      ),
    },
    build: _auditScreenHealthPrompt,
  ),
];

/// MCP Prompts (task 17): `flutterpilot_guide` plus four intent-driven
/// workflows an agent can fetch instead of guessing a tool sequence.
mixin _PromptsMixin on _FlutterPilotServerBase {
  void _registerPrompts() {
    server.registerPrompt(
      _guidePromptName,
      title: _guidePromptTitle,
      description: _guidePromptDescription,
      callback: (args, extra) async => _guidePromptResult(),
    );
    for (final spec in _workflowPrompts) {
      server.registerPrompt(
        spec.name,
        title: spec.title,
        description: spec.description,
        argsSchema: spec.arguments,
        callback: (args, extra) => _promptResult(spec, args),
      );
    }
  }

  /// The prompts `prompts/list` returns, for tests.
  List<Map<String, dynamic>> promptListJson() => [
    {
      'name': _guidePromptName,
      'title': _guidePromptTitle,
      'description': _guidePromptDescription,
      'arguments': const <Object>[],
    },
    for (final spec in _workflowPrompts)
      {
        'name': spec.name,
        'title': spec.title,
        'description': spec.description,
        'arguments': [
          for (final entry in spec.arguments.entries)
            PromptArgument(
              name: entry.key,
              description: entry.value.description,
              required: entry.value.required,
            ).toJson(),
        ],
      },
  ];

  /// Renders one prompt the way `prompts/get` does, for tests. An unknown
  /// [name] fails the way the protocol does.
  GetPromptResult getPromptForTest(String name, {Map<String, dynamic>? args}) {
    if (name == _guidePromptName) return _guidePromptResult();
    for (final spec in _workflowPrompts) {
      if (spec.name == name) return _promptResult(spec, args);
    }
    throw McpError(ErrorCode.methodNotFound.value, "Prompt '$name' not found");
  }

  static GetPromptResult _guidePromptResult() => GetPromptResult(
    description: _guidePromptResultDescription,
    messages: [
      PromptMessage(
        role: PromptMessageRole.user,
        content: TextContent(text: guidePrompt),
      ),
    ],
  );

  static GetPromptResult _promptResult(
    _PromptSpec spec,
    Map<String, dynamic>? args,
  ) => GetPromptResult(
    description: spec.description,
    messages: [
      PromptMessage(
        role: PromptMessageRole.user,
        content: TextContent(text: spec.build(args ?? const {})),
      ),
    ],
  );
}
