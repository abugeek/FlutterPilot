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

  group('prepareLaunch', () {
    LaunchCommand flutterRun(String? device) => LaunchCommand([
      'flutter',
      'run',
      if (device != null) ...['-d', device],
    ], fromConfig: false);

    test('a relaunch keeps the device the running app is on', () async {
      final stopped = <String>[];
      final plan = await prepareLaunch(
        relaunch: true,
        chooseDevice: true,
        runningPlatform: 'windows',
        // The running app names its device, so nothing is listed (field
        // test #346).
        listDevices: () async => throw StateError('no listing needed'),
        commandFor: flutterRun,
        stop: () async => stopped.add('stopped'),
      );
      expect(plan.refusal, isNull);
      expect(plan.device, 'windows');
      expect(plan.deviceWasRunning, isTrue);
      expect('${plan.command}', 'flutter run -d windows');
      expect(stopped, ['stopped'], reason: 'the app it replaces is stopped');
    });

    test('the device the caller asked for wins over the running one', () async {
      var stopped = false;
      final plan = await prepareLaunch(
        relaunch: true,
        chooseDevice: true,
        requested: ' chrome ',
        runningPlatform: 'windows',
        listDevices: () async => throw StateError('no listing needed'),
        commandFor: flutterRun,
        stop: () async => stopped = true,
      );
      expect(plan.device, 'chrome');
      expect(plan.deviceWasRunning, isFalse);
      expect(stopped, isTrue);
    });

    test(
      'several devices and nothing running refuse, before stopping',
      () async {
        var stopped = false;
        final plan = await prepareLaunch(
          relaunch: true,
          chooseDevice: true,
          // Nothing is connected: no platform names the device.
          runningPlatform: null,
          listDevices: () async => ['windows', 'chrome', 'edge'],
          commandFor: (_) => fail('a refusal must not resolve a command'),
          stop: () async => stopped = true,
        );
        expect(plan.refusal, contains('windows, chrome, edge'));
        expect(plan.refusal, contains('launch_app(device: "windows")'));
        expect(plan.command, isNull);
        expect(stopped, isFalse, reason: 'the app stays up');
      },
    );

    test('one device keeps a fresh launch working as before', () async {
      final plan = await prepareLaunch(
        relaunch: false,
        chooseDevice: true,
        listDevices: () async => ['windows'],
        commandFor: flutterRun,
        stop: () async => fail('a fresh launch has nothing to stop'),
      );
      expect(plan.refusal, isNull);
      // `flutter run` picks the only device, as it did before.
      expect(plan.device, isNull);
      expect('${plan.command}', 'flutter run');
    });

    test('a command that cannot be resolved does not stop the app', () async {
      var stopped = false;
      await expectLater(
        prepareLaunch(
          relaunch: true,
          chooseDevice: true,
          requested: 'windows',
          listDevices: () async => const [],
          commandFor: (_) => throw const FormatException('bad launch.json'),
          stop: () async => stopped = true,
        ),
        throwsFormatException,
      );
      expect(stopped, isFalse);
    });

    test(
      "the project's own command decides, so no device is refused",
      () async {
        var stopped = false;
        final plan = await prepareLaunch(
          relaunch: true,
          // launch.json carries the command, so `device` is not ours.
          chooseDevice: false,
          requested: 'chrome',
          runningPlatform: 'windows',
          listDevices: () async => ['windows', 'chrome', 'edge'],
          commandFor: (device) {
            expect(device, isNull);
            return const LaunchCommand(['./scripts/run.sh'], fromConfig: true);
          },
          stop: () async => stopped = true,
        );
        expect(plan.refusal, isNull);
        expect(plan.device, isNull);
        expect(stopped, isTrue);
      },
    );
  });

  group('deviceForPlatform', () {
    test('names the desktop device, not a browser or a phone', () {
      // A desktop app runs on the device called windows/macos/linux; a
      // browser or a phone id cannot be read off the platform (field test
      // #346).
      expect(deviceForPlatform('windows'), 'windows');
      expect(deviceForPlatform('macos'), 'macos');
      expect(deviceForPlatform('linux'), 'linux');
      expect(deviceForPlatform('android'), isNull);
      expect(deviceForPlatform('ios'), isNull);
      expect(deviceForPlatform('linux', isWeb: true), isNull);
      expect(deviceForPlatform(null), isNull);
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

  test('the supervisor starts a batch file named in the app folder', () async {
    // `flutter` is `flutter.bat` on Windows: the supervisor resolves such a
    // name instead of failing with "The system cannot find the file
    // specified" (field test #327).
    File(
      '${tmp.path}/on_path.bat',
    ).writeAsStringSync('@echo off\r\necho started from a batch file\r\n');
    final code = await superviseLaunch([tmp.path, 'on_path.bat']);
    final log = File('${tmp.path}/$launchLogFile').readAsStringSync();
    expect(log, contains('started from a batch file'));
    expect(code, 0);
  }, skip: Platform.isWindows ? false : 'Windows only');

  test('killLaunchTree ends the launch shell and what it started', () async {
    final calls = <(String, List<String>)>[];
    await killLaunchTree(
      4321,
      isWindows: true,
      run: (executable, arguments) async {
        calls.add((executable, arguments));
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(calls, hasLength(1));
    expect(calls.single.$1, 'taskkill');
    // `/T` is the point: the launch is cmd.exe running flutter.bat, and its
    // build and app are children of it (field test #327).
    expect(calls.single.$2, ['/T', '/F', '/PID', '4321']);
  });

  test('killLaunchTree outside Windows does not go through taskkill', () async {
    var called = false;
    await killLaunchTree(
      999999999,
      isWindows: false,
      run: (executable, arguments) async {
        called = true;
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(called, isFalse);
  });

  test('a new launch keeps the previous output', () {
    final log = File('${tmp.path}/$launchLogFile')
      ..createSync(recursive: true)
      ..writeAsStringSync('Slow frame 1454 ms on /home/owner\n');
    startLaunchLog(tmp);
    expect(log.readAsStringSync(), isEmpty);
    expect(
      File('${tmp.path}/$previousLaunchLogFile').readAsStringSync(),
      contains('Slow frame 1454 ms'),
    );
    // A launch that printed nothing does not replace it.
    startLaunchLog(tmp);
    expect(
      File('${tmp.path}/$previousLaunchLogFile').readAsStringSync(),
      contains('Slow frame 1454 ms'),
    );
  });

  test('the log tail keeps the last lines', () {
    final log = [for (var i = 0; i < 100; i++) 'line $i', ''].join('\n');
    final tail = launchLogTail(log, lines: 3);
    expect(tail, 'line 97\nline 98\nline 99');
  });
}

void launchPhaseTests() {
  test('launchPhase names the last stage of the build', () {
    expect(launchPhase(''), isNull);
    expect(
      launchPhase(
        'Launching lib/main.dart on iPhone in debug mode...\nRunning Xcode build...',
      ),
      contains('compiling the iOS app'),
    );
    expect(
      launchPhase('Running Xcode build...\nXcode build done.   13.9s\n'),
      contains('installing'),
    );
    expect(
      launchPhase(
        'Running Gradle task \'assembleDebug\'...\nInstalling build/app.apk...',
      ),
      'installing on the device',
    );
    expect(
      launchPhase(
        'Installing and launching...\nSyncing files to device iPhone',
      ),
      contains('first frame'),
    );
  });
}
