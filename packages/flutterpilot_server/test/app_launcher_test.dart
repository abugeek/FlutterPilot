import 'dart:io';

import 'package:flutterpilot_server/src/app_launcher.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('fp_launch_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory app(String path, {bool main = true}) {
    final dir = Directory('${tmp.path}/$path')..createSync(recursive: true);
    File('${dir.path}/pubspec.yaml').writeAsStringSync(
      'name: a\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    if (main) {
      File('${dir.path}/lib/main.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');
    }
    return dir;
  }

  group('launchCommandFor', () {
    test('flutter run with the URI file, device, target and mode', () {
      final command = launchCommandFor(
        app('a'),
        device: 'macos',
        target: 'lib/dev.dart',
        mode: 'profile',
      );
      expect(command.fromConfig, isFalse);
      expect(command.command, [
        'flutter',
        'run',
        '--vmservice-out-file=.dart_tool/flutterpilot_vm_uri',
        '--profile',
        '-d',
        'macos',
        '-t',
        'lib/dev.dart',
      ]);
    });

    test("the project's own command wins", () {
      final dir = app('a');
      File('${dir.path}/flutterpilot/launch.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"command": ["./scripts/run_macos.sh", "-t", "tool/pilot_main.dart"]}',
        );
      final command = launchCommandFor(dir, device: 'chrome');
      expect(command.fromConfig, isTrue);
      expect('$command', './scripts/run_macos.sh -t tool/pilot_main.dart');
    });

    test('a launch.json without a command list says what it needs', () {
      final dir = app('a');
      final file = File('${dir.path}/flutterpilot/launch.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"command": "flutter run"}');
      expect(
        () => launchCommandFor(dir),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('a list of strings'),
          ),
        ),
      );
      file.writeAsStringSync('{nope');
      expect(() => launchCommandFor(dir), throwsFormatException);
    });
  });

  test('flutterAppsUnder finds apps, not packages or build output', () {
    app('apps/mobile');
    app('packages/ui', main: false);
    app('apps/mobile/build/copy');
    final found = flutterAppsUnder([tmp]);
    expect(found.map((d) => d.path.replaceAll(r'\', '/')), [
      endsWith('apps/mobile'),
    ]);
  });

  test('the VM service URI is read from flutter run output', () {
    expect(
      vmServiceUriIn(
        'Syncing files to device macOS...\n'
        'A Dart VM Service on macOS is available at: http://127.0.0.1:55016/_h5E71gZXxk=/\n'
        'The Flutter DevTools debugger and profiler on macOS is available at: '
        'http://127.0.0.1:55016/_h5E71gZXxk=/devtools/?uri=ws://127.0.0.1:55016/_h5E71gZXxk=/ws\n',
      ),
      'http://127.0.0.1:55016/_h5E71gZXxk=/',
    );
    expect(
      vmServiceUriIn('Debug service listening on ws://127.0.0.1:60001/abc=/ws'),
      'ws://127.0.0.1:60001/abc=/ws',
    );
    expect(vmServiceUriIn('Building macOS application...'), isNull);
  });

  test(
    'the supervisor logs the output, the exit code and clears its pid',
    () async {
      final code = await superviseLaunch([
        tmp.path,
        Platform.resolvedExecutable,
        '--version',
      ]);
      final log = File('${tmp.path}/$launchLogFile').readAsStringSync();
      expect(code, 0);
      expect(log, contains('Dart SDK version'));
      expect(launchExitCodeIn(log), 0);
      expect(launchLogTail(log), isNot(contains('[flutterpilot]')));
      expect(File('${tmp.path}/$launchPidFile').existsSync(), isFalse);
      expect(runningLaunchPid(tmp), isNull);
    },
  );

  test('a command that cannot start is an exit code with the reason', () async {
    final code = await superviseLaunch([tmp.path, './no_such_script.sh']);
    final log = File('${tmp.path}/$launchLogFile').readAsStringSync();
    expect(code, 127);
    expect(launchExitCodeIn(log), 127);
    expect(launchLogTail(log), contains('no_such_script.sh'));
  });

  test('the log tail keeps the last lines', () {
    final log = [for (var i = 0; i < 100; i++) 'line $i', ''].join('\n');
    final tail = launchLogTail(log, lines: 3);
    expect(tail, 'line 97\nline 98\nline 99');
  });
}
