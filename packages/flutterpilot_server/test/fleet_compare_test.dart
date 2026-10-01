import 'package:flutterpilot_server/src/fleet_compare.dart';
import 'package:test/test.dart';

void main() {
  final steps = [
    (tool: 'tap_widget', arguments: <String, dynamic>{'key': 'Log in'}),
    (tool: 'assert_widget', arguments: <String, dynamic>{'text': 'Welcome'}),
  ];

  DeviceRun run(
    String device, {
    List<bool> steps = const [true, true],
    String route = '/home',
    List<String> tappable = const ['Log out'],
    int errors = 0,
  }) => DeviceRun(device)
    ..steps.addAll([
      for (final ok in steps)
        (
          ok: ok,
          text: ok
              ? '(12ms)\nTapped'
              : '(3ms)\nWidget not found: "Welcome"\nHINT: …',
        ),
    ])
    ..route = route
    ..tappable = tappable
    ..errors = errors;

  test('devices that agree read in a few lines', () {
    final text = describeFleetRun(steps, [run('macos'), run('iphone')]);
    expect(text, '''
Ran 2 step(s) on 2 devices (macos, iphone).
1. tap_widget (key: "Log in"): ✅ all
2. assert_widget (text: "Welcome"): ✅ all
All devices agree: same steps passed, same final screen.''');
  });

  test('a step failing on one device, and how the screens differ', () {
    final text = describeFleetRun(steps, [
      run('macos'),
      run('pixel', steps: [true, false], route: '/login', tappable: ['Log in']),
      run('web', errors: 2, tappable: ['Log out', 'Install app']),
    ]);
    expect(
      text,
      contains(
        '2. assert_widget (text: "Welcome"): ✅ macos, web · '
        '❌ pixel: Widget not found: "Welcome"',
      ),
    );
    expect(text, contains('- route: macos, web "/home"; pixel "/login"'));
    expect(text, contains('- tappable on macos, web only: "Log out"'));
    expect(text, contains('- tappable on pixel only: "Log in"'));
    expect(text, contains('- tappable on web only: "Install app"'));
    expect(text, contains('- new errors: web 2'));
  });

  test('a device stopped earlier, and one not reachable', () {
    final down = DeviceRun('android')
      ..unreachable = 'Device "android" is not running';
    final text = describeFleetRun(steps, [
      run('macos'),
      run('iphone', steps: [false]),
      down,
    ]);
    expect(text, contains('⚠️ android: Device "android" is not running'));
    expect(
      text,
      contains(
        '2. assert_widget (text: "Welcome"): ✅ macos · – iphone (stopped earlier)',
      ),
    );
    expect(text, isNot(contains('All devices agree')));
  });

  test('reads the snapshot the SDK returns', () {
    final r = DeviceRun('macos')
      ..readSnapshot({
        'route': {'current': '/saved'},
        'interactiveElements': [
          {'type': 'IconButton', 'text': 'Bookmark'},
          {'type': 'ListTile', 'key': 'story_1'},
          {'type': 'FloatingActionButton'},
        ],
        'errorCount': 7,
      });
    expect(r.route, '/saved');
    expect(r.tappable, ['Bookmark', 'story_1', 'FloatingActionButton']);
    // No baseline (an older SDK): no count rather than a wrong one.
    expect(r.errors, 0);
  });

  test('counts only the errors raised during the steps', () {
    final r = DeviceRun('iphone')
      ..readBaseline({'errorCount': 5})
      ..readSnapshot({
        'errorCount': 7,
        'lastError': 'A RenderFlex overflowed by 144 pixels on the right.',
      });
    expect(r.errors, 2);
    expect(
      describeFleetRun(const [], [r, DeviceRun('mac')]),
      contains(
        '- new errors: iphone 2 (last: A RenderFlex overflowed by 144 '
        'pixels on the right.)',
      ),
    );
  });
}
