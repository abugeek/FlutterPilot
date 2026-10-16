import 'package:fp_server/src/action_chain.dart';
import 'package:test/test.dart';

void main() {
  test('a step is a tool call, as in run_on_devices', () {
    final step = chainStep({
      'tool': 'press_key',
      'arguments': {'key': 'enter'},
    });
    expect(step?.tool, 'press_key');
    expect(step?.arguments, {'key': 'enter'});
    expect(chainStep({'tool': 'wait_for'})?.arguments, isEmpty);
    expect(chainStep('tap'), isNull);
    expect(chainStep({'tool': 'tap_widget', 'arguments': 'Save'}), isNull);
  });

  test('the former action/target shape still reads', () {
    final tap = chainStep({'action': 'tap', 'target': 'Save'});
    expect(tap?.tool, 'tap_widget');
    expect(tap?.arguments, {'key': 'Save'});
    final type = chainStep({
      'action': 'enter_text',
      'target': 'Title',
      'text': 'Milk',
    });
    expect(type?.tool, 'enter_text');
    expect(type?.arguments, {'key': 'Title', 'text': 'Milk'});
    expect(chainStep({'action': 'swipe', 'target': 'List'}), isNull);
  });

  test('plain taps and text entries run inside the app', () {
    expect(inAppChainAction((tool: 'tap_widget', arguments: {'key': 'Save'})), {
      'action': 'tap',
      'target': 'Save',
    });
    expect(
      inAppChainAction((
        tool: 'enter_text',
        arguments: {'key': 'Title', 'text': 'Milk'},
      )),
      {'action': 'enter_text', 'target': 'Title', 'text': 'Milk'},
    );
  });

  test('what the in-app chain cannot do goes through the tool', () {
    for (final ChainStep step in [
      (tool: 'tap_widget', arguments: {'key': 'Save', 'gesture': 'long'}),
      (tool: 'tap_widget', arguments: {'x': 10, 'y': 20}),
      // The tool clears a field for ""; the in-app chain does not.
      (tool: 'enter_text', arguments: {'key': 'Title', 'text': ''}),
      (tool: 'enter_text', arguments: {'text': 'into the focused field'}),
      (tool: 'assert_widget', arguments: {'key': 'Save'}),
    ]) {
      expect(inAppChainAction(step), isNull, reason: '$step');
    }
  });

  test('a finished chain shows each step and the last one in full', () {
    expect(
      describeChain(
        ['tap_widget', 'assert_widget'],
        [
          'Widget tapped "Save". Route unchanged (/).\nTappable now (2): …',
          'OK',
        ],
        failed: false,
      ),
      'Action chain: 2/2 steps done.\n'
      'Step 1 tap_widget: Widget tapped "Save". Route unchanged (/).\n'
      'Step 2 assert_widget: OK',
    );
  });

  test('a failed chain says where it stopped and what did not run', () {
    expect(
      describeChain(
        ['tap_widget', 'wait_for', 'press_key'],
        ['Widget tapped "Save".', '"Saved" did not appear\nwithin 3000 ms'],
        failed: true,
      ),
      'Action chain stopped after 1/3 steps.\n'
      'Step 1 tap_widget: Widget tapped "Save".\n'
      'Step 2 wait_for failed: "Saved" did not appear\nwithin 3000 ms\n'
      'Not run: press_key.',
    );
  });

  group('all-step preflight (task 02)', () {
    const allowed = {'tap_widget', 'enter_text', 'press_key', 'gesture_widget'};
    bool available(String tool) => allowed.contains(tool);

    /// A stand-in for `_toolArgGates`: refuses the two required arguments the
    /// tests exercise, otherwise passes the arguments through unchanged.
    ({Map<String, dynamic> args, String? problem}) gate(
      String tool,
      Map<String, dynamic> args,
    ) {
      if (tool == 'press_key' && args['key'] == null) {
        return (
          args: args,
          problem: 'press_key needs key (a string); nothing was done.',
        );
      }
      if (tool == 'enter_text' && args['text'] == null) {
        return (
          args: args,
          problem: 'enter_text needs text (a string); nothing was done.',
        );
      }
      return (args: args, problem: null);
    }

    ChainPreflight preflight(
      Object? steps, {
      String what = 'run in a chain',
      String field = 'steps',
      String emptyProblem = 'steps is empty.',
      String? Function(String tool)? profileRefusal,
    }) => preflightChain(
      steps,
      allowedTools: allowed,
      isAvailable: available,
      profileRefusal: profileRefusal ?? (tool) => null,
      gate: gate,
      what: what,
      field: field,
      emptyProblem: emptyProblem,
    );

    /// What a composite would run: preflight only, then that many steps.
    int wouldRun(ChainPreflight p) => p.ok ? p.steps.length : 0;

    test('an invalid step after valid ones refuses and returns no steps', () {
      final result = preflight([
        {
          'tool': 'tap_widget',
          'arguments': {'key': 'Save'},
        },
        'not a step',
      ]);
      expect(result.ok, isFalse);
      expect(result.steps, isEmpty);
      expect(result.problemStep, 2);
      expect(result.problem, startsWith('steps[1]: not a {"tool"'));
    });

    test('a bad argument on the last step is caught, not a sample', () {
      // The gate records every step it is asked about: the last step's own
      // arguments are validated like the first's.
      final validated = <String>[];
      final result = preflightChain(
        [
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'A'},
          },
          {
            'tool': 'enter_text',
            'arguments': {'text': 'B'},
          },
          {'tool': 'press_key', 'arguments': <String, dynamic>{}},
        ],
        allowedTools: allowed,
        isAvailable: available,
        profileRefusal: (_) => null,
        gate: (tool, args) {
          validated.add(tool);
          return gate(tool, args);
        },
      );
      expect(result.ok, isFalse);
      expect(result.problemStep, 3);
      // Path names the argument of the offending step.
      expect(result.problem, startsWith('steps[2].arguments: press_key needs'));
      expect(validated, ['tap_widget', 'enter_text', 'press_key']);
      // The invalid plan executes zero steps.
      expect(wouldRun(result), 0);

      // The same three steps with valid arguments validate and would run.
      final ok = preflight([
        {
          'tool': 'tap_widget',
          'arguments': {'key': 'A'},
        },
        {
          'tool': 'enter_text',
          'arguments': {'text': 'B'},
        },
        {
          'tool': 'press_key',
          'arguments': {'key': 'enter'},
        },
      ]);
      expect(ok.ok, isTrue);
      expect(wouldRun(ok), 3);
    });

    test('a retired tool is translated before it is checked', () {
      final result = preflight([
        {
          'tool': 'swipe_widget',
          'arguments': {'key': 'Row 0'},
        },
      ]);
      expect(result.ok, isTrue);
      expect(result.steps.single.tool, 'gesture_widget');
      expect(result.steps.single.arguments, {
        'gesture': 'swipe',
        'key': 'Row 0',
      });
    });

    test('a tool outside the family is refused at its path', () {
      final result = preflight([
        {
          'tool': 'tap_widget',
          'arguments': {'key': 'A'},
        },
        {'tool': 'run_on_devices', 'arguments': <String, dynamic>{}},
      ]);
      expect(result.problemStep, 2);
      expect(result.problem, contains('steps[1]: "run_on_devices" can\'t'));
      expect(result.problem, contains('Tools: '));
    });

    test('a scalar array item is not a step', () {
      final result = preflight(['tap']);
      expect(result.problemStep, 1);
      expect(result.problem, startsWith('steps[0]: not a {"tool"'));
    });

    test('the profile refusal is named at its path', () {
      final result = preflight(
        [
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'A'},
          },
          {
            'tool': 'enter_text',
            'arguments': {'text': 'B'},
          },
        ],
        profileRefusal: (tool) => tool == 'enter_text'
            ? '"$tool" is not listed in the core profile.'
            : null,
      );
      expect(result.problemStep, 2);
      expect(
        result.problem,
        'steps[1]: "enter_text" is not listed in the core profile.',
      );
    });

    test('an alias survives preflight for the tool to resolve', () {
      // `target` is an accepted alias of `key`; preflight does not drop it, the
      // tool's own gate (withFormerNames) resolves it at execution.
      final result = preflight([
        {
          'tool': 'tap_widget',
          'arguments': {'target': 'Save'},
        },
      ]);
      expect(result.ok, isTrue);
      expect(result.steps.single.arguments, {'target': 'Save'});
    });

    test('an empty or non-list plan is refused with its own message', () {
      expect(preflight(const []).problem, 'steps is empty.');
      expect(preflight(null).problem, 'steps is empty.');
      expect(preflight('oops').problem, 'steps is empty.');
      expect(
        preflight(
          const [],
          field: 'cycle',
          emptyProblem: 'cycle is empty: give the steps.',
        ).problem,
        'cycle is empty: give the steps.',
      );
      // The field names the array in a per-step refusal.
      final cycle = preflight([
        {'tool': 'nope', 'arguments': <String, dynamic>{}},
      ], field: 'cycle');
      expect(cycle.problem, startsWith('cycle[0]:'));
    });

    test('a single nested call (profile_action) shares the checks', () {
      ({ChainStep? step, String? problem}) single(
        String tool,
        Map<String, dynamic> args, {
        String what = 'run in a chain',
      }) => preflightStep(
        tool,
        args,
        allowedTools: allowed,
        isAvailable: available,
        profileRefusal: (_) => null,
        gate: gate,
        path: 'tool',
        what: what,
      );

      final outside = single('run_on_devices', const {}, what: 'be profiled');
      expect(outside.step, isNull);
      expect(
        outside.problem,
        contains('tool: "run_on_devices" can\'t be profiled.'),
      );

      final missing = single('press_key', const {});
      expect(
        missing.problem,
        'tool.arguments: press_key needs key (a string); nothing was done.',
      );

      final retired = single('swipe_widget', const {'key': 'Row'});
      expect(retired.problem, isNull);
      expect(retired.step?.tool, 'gesture_widget');
      expect(retired.step?.arguments, {'gesture': 'swipe', 'key': 'Row'});
    });
  });
}
