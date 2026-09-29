import 'package:flutterpilot_server/src/test_writer.dart';
import 'package:test/test.dart';

void main() {
  GeneratedTest write(List<Map<String, dynamic>> steps) => writeIntegrationTest(
    name: 'login_flow',
    mainImport: 'package:shop/main.dart',
    steps: steps,
  );

  test('starts the real app and replays steps with their finders', () {
    final t = write([
      {
        'type': 'mock',
        'urlPattern': '/login',
        'statusCode': 200,
        'body': r'{"token":"$x"}',
      },
      {
        'type': 'enterText',
        'finder': "find.widgetWithText(TextField, 'Email')",
        'stable': true,
        'text': "o'neil@x.io",
      },
      {
        'type': 'enterText',
        'finder': "find.widgetWithText(TextField, 'Password')",
        'stable': true,
        'secret': 1,
      },
      {
        'type': 'pressKey',
        'key': 'enter',
        'modifiers': <String>[],
        'inField': true,
      },
      {
        'type': 'tap',
        'finder': "find.text('Log in')",
        'stable': true,
        'target': 'Log in',
      },
      {'type': 'expectText', 'text': 'Welcome', 'exact': false},
    ]);
    final s = t.source;
    expect(s, contains("import 'package:shop/main.dart' as app;"));
    expect(
      s,
      contains("import 'package:flutterpilot_dio/flutterpilot_dio.dart';"),
    );
    expect(s, contains('app.main();'));
    expect(
      s,
      contains(
        r"DioPilotInterceptor.mock('/login', statusCode: 200, "
        r"body: '{"
        '"token":"'
        r"\$x"
        '"}'
        "');",
      ),
    );
    expect(
      s,
      contains(
        "await tester.enterText(find.widgetWithText(TextField, 'Email'), "
        r"'o\'neil@x.io');",
      ),
    );
    // A password is read from a define, never written.
    expect(s, contains("const String.fromEnvironment('FP_SECRET_1')"));
    expect(s, contains('--dart-define=FP_SECRET_1=…'));
    expect(
      s,
      contains(
        'await tester.testTextInput.receiveAction(TextInputAction.done);',
      ),
    );
    expect(s, contains("await _show(tester, find.text('Log in'));"));
    expect(s, contains("await tester.tap(find.text('Log in'));"));
    expect(
      s,
      contains(
        "await _show(tester, find.textContaining('Welcome', "
        'findRichText: true));',
      ),
    );
    expect(s, contains('Future<void> _settle(WidgetTester tester)'));
    expect(t.skipped, isEmpty);
  });

  test('says what it could not replay or found by position', () {
    final t = write([
      {'type': 'skipped', 'what': 'navigate_to /settings'},
      {'type': 'tap', 'finder': 'find.byType(Icon).at(3)', 'stable': false},
      {'type': 'pressKey', 'key': 'F13', 'modifiers': <String>[]},
      {
        'type': 'pressKey',
        'key': 'a',
        'modifiers': ['ctrl'],
      },
    ]);
    expect(t.skipped, ['navigate_to /settings', 'press_key "F13"']);
    expect(t.unstable, ['find.byType(Icon).at(3)']);
    expect(
      t.source,
      contains(
        'await tester.sendKeyDownEvent(LogicalKeyboardKey.control);\n'
        '    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);\n'
        '    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);',
      ),
    );
    expect(t.source, isNot(contains('flutterpilot_dio')));
  });

  test('a failure names the step it stopped at', () {
    const source = '''
    // 7. enter text
    await tester.enterText(find.byType(TextField), 'x');
    // 8. expect text
    await _show(tester, find.text('Done'));
''';
    const output = '''
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════
The following TestFailure was thrown running a test:
Expected: at least one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Done": []>

When the exception was thrown, this was the stack:
#4      _show (file:///app/integration_test/flow_test.dart:9:3)
#5      main.<anonymous closure> (file:///app/integration_test/flow_test.dart:4:5)
''';
    final text = describeTestFailure(output, source, 'flow_test.dart');
    expect(text, startsWith('Failed at step 8, expect text (line 4).\n'));
    expect(text, contains('Found 0 widgets with text "Done"'));
    expect(text, isNot(contains('When the exception')));
  });
}
