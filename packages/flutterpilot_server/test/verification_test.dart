import 'package:flutterpilot_server/src/verification.dart';
import 'package:test/test.dart';

void main() {
  Verification start() => Verification('Login', [
    'A wrong password shows an error',
    'A right password opens Home',
    'The password is never shown',
  ]);

  test('a pass needs a passing check; driving alone is not verified', () {
    final v = start();
    v.current = v.criteria[0];
    v.record(
      'enter_text',
      {'target': 'Password', 'text': 'hunter2'},
      'Typed "•••••••" into "Password".',
      isError: false,
    );
    v.record(
      'assert_widget',
      {'text': 'Wrong password'},
      '{"status":"passed","text":"Wrong password"}',
      isError: false,
    );
    v.current = v.criteria[1];
    v.record(
      'tap_widget',
      {'key': 'Log in'},
      'Widget tapped "Log in".',
      isError: false,
    );
    // Reads are not evidence.
    v.record('get_widget_tree', {}, 'Home…', isError: false);

    expect(v.criteria[0].verdict, Verdict.pass);
    expect(v.criteria[1].verdict, Verdict.unverified);
    expect(v.criteria[1].steps, hasLength(1));
    expect(v.criteria[2].verdict, Verdict.unverified);
    expect(v.headline, 'INCOMPLETE: 1 of 3 criteria passed, 2 not verified');

    final md = v.toMarkdown(app: 'on macos');
    expect(md, contains('| 1 | A wrong password shows an error | ✅ PASS |'));
    expect(md, contains('✔ `assert_widget` (text: "Wrong password") → passed'));
    // An action shows its response (masked), never what was typed.
    expect(md, isNot(contains('hunter2')));
    expect(md, contains('Nothing was done or checked for it.'));
  });

  test('a failed check fails it, naming a failed action before it', () {
    final v = start();
    v.current = v.criteria[1];
    v.record(
      'enter_text',
      {'target': 'Pasword'},
      '[extensionError] Widget not found matching: "Pasword".\nHINT: …',
      isError: true,
    );
    v.record(
      'wait_for',
      {'key': 'Home', 'timeoutMs': 5000},
      '[extensionError] Timeout: "Home" did not appear',
      isError: true,
    );
    final c = v.criteria[1];
    expect(c.verdict, Verdict.fail);
    expect(
      c.reason,
      'Check failed: `wait_for` (key: "Home") → Timeout: "Home" did not '
      'appear. Before it `enter_text` failed: Widget not found matching: '
      '"Pasword".',
    );
    expect(v.headline, startsWith('FAILED: 0 of 3 criteria passed, 1 failed'));

    // Picking it again starts over.
    c.reset();
    expect(c.verdict, Verdict.unverified);
  });

  test('app errors fail a criterion; layout warnings do not', () {
    final v = start();
    final c = v.criteria[0];
    v.current = c;
    v.record('assert_widget', {'text': 'x'}, 'passed', isError: false);
    c.warnings.add('A RenderFlex overflowed by 12 pixels on the right.');
    expect(c.verdict, Verdict.pass);
    c.errors.add('Null check operator used on a null value');
    expect(c.verdict, Verdict.fail);
    expect(c.reason, 'The app threw 1 error(s) meanwhile.');
  });

  test('a long request list is cut, counting the failures in the rest', () {
    final v = start();
    final c = v.criteria[0]..steps.clear();
    for (var i = 0; i < 20; i++) {
      c.requests.add('GET https://x/item/$i → ${i == 18 ? 500 : 200}');
    }
    final md = v.toMarkdown();
    expect(md, contains('- GET https://x/item/14 → 200'));
    expect(md, isNot(contains('item/15 ')));
    expect(md, contains('- … and 5 more (1 of them failed)'));
  });
}
