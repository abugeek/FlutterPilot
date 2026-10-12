import 'package:flutterpilot_cli/src/smoke.dart';
import 'package:test/test.dart';

void main() {
  test('routePaths joins nested go_router paths, drops parameters', () {
    const text = '''{"stack":["/"],"routes":[
      {"type":"GoRoute","path":"/","children":[
        {"type":"GoRoute","path":"item/:id"},
        {"type":"GoRoute","path":"about"}]},
      {"type":"ShellRoute","children":[{"type":"GoRoute","path":"/settings","children":[
        {"type":"GoRoute","path":"profile"}]}]},
      {"type":"GoRoute","path":"/files/*"}]}''';
    expect(routePaths(text), ['/', '/about', '/settings', '/settings/profile']);
    expect(routePaths('no table here'), isEmpty);
    expect(routePaths('{"stack":[]}'), isEmpty);
  });

  test('summary fields', () {
    const s = '• Route: /home (Depth: 2)\n• Uncaught Errors (3): boom\n';
    expect(currentRoute(s), '/home');
    expect(uncaughtErrors(s), 3);
    expect(uncaughtErrors('• Uncaught Errors (0): None'), 0);
  });

  test('the report lists findings only for screens that have them', () {
    final screens = [
      ScreenResult('/', audit: 'No layout overflows, small tap targets.'),
      ScreenResult(
        '/cart',
        audit: 'Tap targets under 48dp:\n- Remove',
        shot: 'cart.png',
      ),
      ScreenResult(
        '/pay',
        audit: 'No layout overflows, small tap targets.',
        errors: 'RangeError',
      ),
    ];
    final r = smokeReport(
      screens,
      at: DateTime.utc(2026, 10, 12),
      device: 'pixel',
      app: 'shop',
    );
    expect(r, contains('3 screens, 2 with findings'));
    expect(r, contains('| `/` | clean | none |'));
    expect(r, contains('| `/cart` | findings | none |'));
    expect(r, contains('| `/pay` | clean | yes |'));
    expect(r, contains('![/cart](cart.png)'));
    expect(r, contains('RangeError'));
    expect(r.contains('## `/`'), isFalse);
    expect(
      smokeReport([
        ScreenResult('/', audit: 'No layout overflows'),
      ], at: DateTime.utc(2026)),
      contains('all clean'),
    );
  });

  test('routeFileName', () {
    expect(routeFileName('/'), 'root');
    expect(routeFileName('/a/b?x=1'), 'a_b_x_1');
  });

  test('long findings are cut in the report', () {
    final r = smokeReport([
      ScreenResult('/', audit: 'Layout overflows ${'x' * 9000}'),
    ], at: DateTime.utc(2026));
    expect(r.length, lessThan(5000));
    expect(r, contains('more characters'));
  });
}
