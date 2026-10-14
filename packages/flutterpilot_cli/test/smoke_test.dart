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

  test("a screen clean at the app's scale but not at 2 gets its own block", () {
    final r = smokeReport(
      [
        ScreenResult(
          '/checkout',
          audit: 'No layout overflows, small tap targets.',
          auditLarge: 'Layout overflows (1):\n- Row: at (16, 372), 1232x40',
          shot: 'checkout.png',
        ),
      ],
      at: DateTime.utc(2026, 10, 14),
      app: 'shop',
      textScalePass: true,
    );
    expect(r, contains('text scale 1 and 2'));
    expect(r, contains('| `/checkout` | findings at 2x | none |'));
    expect(r, contains('At text scale 2:'));
    expect(r, contains('Row: at (16, 372)'));
    // Not "at the app's scale": that pass was clean.
    expect(r.contains("At the app's text scale:"), isFalse);

    // Only the large pass: a finding all the same.
    expect(
      ScreenResult(
        '/',
        audit: 'No layout overflows',
        auditLarge: 'Layout overflows (1):\n- Row',
      ).ok,
      isFalse,
    );
    expect(
      ScreenResult(
        '/',
        audit: 'No layout overflows',
        auditLarge: 'No layout overflows',
      ).ok,
      isTrue,
    );
  });

  test('findings in both passes are labelled apart', () {
    final r = smokeReport(
      [
        ScreenResult(
          '/checkout',
          audit: 'Layout overflows (1):\n- Row: at (16, 252), 1232x20',
          auditLarge: 'Layout overflows (1):\n- Row: at (16, 372), 1232x40',
        ),
      ],
      at: DateTime.utc(2026, 10, 14),
      textScalePass: true,
    );
    expect(r, contains('| `/checkout` | findings | none |'));
    expect(r, contains("At the app's text scale:"));
    expect(r, contains('1232x20'));
    expect(r, contains('At text scale 2:'));
    expect(r, contains('1232x40'));
  });

  test('a clean second pass leaves the screen clean and unlabelled', () {
    final r = smokeReport(
      [
        ScreenResult(
          '/',
          audit: 'No layout overflows, small tap targets.',
          auditLarge: 'No layout overflows, small tap targets.',
        ),
      ],
      at: DateTime.utc(2026, 10, 14),
      textScalePass: true,
    );
    expect(r, contains('all clean'));
    expect(r, contains('| `/` | clean | none |'));
    expect(r, contains('text scale 1 and 2'));
    expect(r.contains('At text scale 2:'), isFalse);
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
