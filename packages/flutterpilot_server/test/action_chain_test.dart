import 'package:flutterpilot_server/src/action_chain.dart';
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
}
