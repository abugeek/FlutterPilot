import 'dart:io';

import 'package:flutterpilot_server/src/window_size.dart';
import 'package:test/test.dart';

void main() {
  test('parses WIDTHxHEIGHT', () {
    expect(parseWindowSize('390x844'), (width: 390, height: 844));
    expect(parseWindowSize(' 1280 × 860 '), (width: 1280, height: 860));
    expect(parseWindowSize('390'), isNull);
    expect(parseWindowSize('wide'), isNull);
  });

  test('resizes the window of the app\'s own process', () async {
    final calls = <List<String>>[];
    final problem = await resizeAppWindow(
      operatingSystem: 'macos',
      pid: 4242,
      width: 390,
      height: 844,
      run: (exe, args) async {
        calls.add([exe, ...args]);
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(problem, isNull);
    expect(calls.single.first, 'osascript');
    expect(calls.single.last, contains('unix id is 4242'));
    expect(calls.single.last, contains('{390, 844}'));
    // Not `window 1`: a system dialog of the app can be in front.
    expect(calls.single.last, contains('AXStandardWindow'));
  });

  test('says so when the platform has no window to resize', () async {
    final problem = await resizeAppWindow(
      operatingSystem: 'android',
      pid: 1,
      width: 390,
      height: 844,
      run: (_, _) async => fail('must not run a host command'),
    );
    expect(problem, contains('macOS and Windows desktop apps only'));
  });

  test('on Windows the viewport, not the frame, gets the size', () async {
    final calls = <List<String>>[];
    final problem = await resizeAppWindow(
      operatingSystem: 'windows',
      pid: 4242,
      width: 390,
      height: 844,
      run: (exe, args) async {
        calls.add([exe, ...args]);
        return ProcessResult(1, 0, '', '');
      },
    );
    expect(problem, isNull);
    expect(calls.single.first, 'powershell');
    final script = calls.single.last;
    expect(script, contains('Get-Process -Id 4242'));
    // The frame around the client area is added to the requested size.
    expect(script, contains(r'Round(390 * $d) + ($o.R - $o.L) - $c.R'));
    expect(script, contains(r'Round(844 * $d) + ($o.B - $o.T) - $c.B'));

    expect(
      await resizeAppWindow(
        operatingSystem: 'windows',
        pid: 1,
        width: 390,
        height: 844,
        run: (_, _) async => ProcessResult(1, 2, '', 'no window\n'),
      ),
      contains('has no window'),
    );
  });

  test('names the permission when macOS refuses', () async {
    final problem = await resizeAppWindow(
      operatingSystem: 'macos',
      pid: 1,
      width: 390,
      height: 844,
      run: (_, _) async => ProcessResult(
        1,
        1,
        '',
        'execution error: System Events got an error: osascript is not '
            'allowed assistive access. (-25211)',
      ),
    );
    expect(problem, contains('Accessibility'));
  });

  test('reads the window size macOS reports', () async {
    expect(
      await readAppWindowSize(
        7,
        run: (_, args) async {
          expect(args.last, contains('unix id is 7'));
          return ProcessResult(1, 0, '700, 600\n', '');
        },
      ),
      '700x600',
    );
    expect(
      await readAppWindowSize(
        7,
        run: (_, _) async => ProcessResult(1, 1, '', 'x'),
      ),
      isNull,
    );
  });
}
