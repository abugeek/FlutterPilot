import 'package:flutterpilot_server/src/screen_memory.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2026, 10, 11, 9);
  final screen = ['All', 'Open', 'Done', 'Buy milk', 'Call Sam', 'Settings'];

  test('the first response lists the elements', () {
    expect(
      ScreenMemory().tappable(['Save', 'Cancel'], 2, at: t0),
      'Tappable now (2): "Save", "Cancel"',
    );
  });

  test('an unchanged screen is not listed again', () {
    final memory = ScreenMemory()..tappable(screen, 6, at: t0);
    expect(
      memory.tappable(screen, 6, at: t0),
      'Tappable now (6): same as after the previous call.',
    );
  });

  test('a small change is said as a difference', () {
    final memory = ScreenMemory()..tappable(screen, 6, at: t0);
    expect(
      memory.tappable(
        ['All', 'Open', 'Done', 'Buy milk', 'Settings', 'Undo'],
        6,
        at: t0,
      ),
      'Tappable now (6): as after the previous call, plus "Undo", '
      'without "Call Sam".',
    );
  });

  test('another screen is listed in full', () {
    final memory = ScreenMemory()..tappable(screen, 6, at: t0);
    expect(
      memory.tappable(['Title', 'Save'], 2, at: t0),
      'Tappable now (2): "Title", "Save"',
    );
  });

  test('the full list comes back every fourth time and after two minutes', () {
    final memory = ScreenMemory();
    final lines = [
      for (var i = 0; i < 6; i++) memory.tappable(screen, 6, at: t0),
    ];
    expect(
      [for (final l in lines) l.contains('"All"')],
      [true, false, false, false, true, false],
    );
    expect(
      memory.tappable(screen, 6, at: t0.add(const Duration(minutes: 3))),
      contains('"All"'),
    );
  });

  test('more elements below the shown ones is a change', () {
    final memory = ScreenMemory()..tappable(screen, 6, at: t0);
    expect(memory.tappable(screen, 9, at: t0), contains('(9): as after'));
  });
}
