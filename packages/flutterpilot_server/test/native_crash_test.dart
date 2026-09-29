import 'dart:convert';
import 'dart:io';

import 'package:flutterpilot_server/src/native_crash.dart';
import 'package:test/test.dart';

/// The shape of a simulator app's `.ips` report after an uncaught
/// NSException (Firebase rejecting its API key, findings #161), trimmed.
String _ips({Map<String, dynamic>? asi, bool exceptionBacktrace = true}) {
  const app =
      '/Users/USER/Library/Developer/CoreSimulator/Devices/X/data/'
      'Containers/Bundle/Application/Y/Runner.app';
  final body = {
    'pid': 35369,
    'procName': 'Runner',
    'captureTime': '2026-09-28 09:56:00.8018 +0500',
    'exception': {'type': 'EXC_CRASH', 'signal': 'SIGABRT'},
    'termination': {'indicator': 'Abort trap: 6'},
    'asi': ?asi,
    'usedImages': [
      {'name': 'Runner.debug.dylib', 'path': '$app/Runner.debug.dylib'},
      {'name': 'libobjc.A.dylib', 'path': '/Volumes/VOLUME/*/libobjc.A.dylib'},
      {
        'name': 'CoreFoundation',
        'path': '/Volumes/VOLUME/*/CoreFoundation.framework/CoreFoundation',
      },
      {'name': 'libsystem_c.dylib', 'path': '/usr/lib/libsystem_c.dylib'},
    ],
    if (exceptionBacktrace)
      'lastExceptionBacktrace': [
        {'symbol': '__exceptionPreprocess', 'imageIndex': 2},
        {'symbol': 'objc_exception_throw', 'imageIndex': 1},
        {
          'symbol': '+[FIRInstallations validateAPIKey:]',
          'sourceFile': 'FIRInstallations.m',
          'sourceLine': 162,
          'imageIndex': 0,
        },
        {
          'symbol': 'static AppDelegate.\$main()',
          'sourceFile': '/<compiler-generated>',
          'imageIndex': 0,
        },
      ],
    'threads': [
      {'frames': <Object>[]},
      {
        'triggered': true,
        'frames': [
          {'symbol': 'abort', 'imageIndex': 3},
          {'symbol': 'main', 'imageIndex': 0},
        ],
      },
    ],
  };
  return '{"app_name":"Runner","bug_type":"309"}\n${jsonEncode(body)}';
}

void main() {
  group('parseIpsReport', () {
    test('an uncaught exception: where it was thrown, in app code', () {
      final r = parseIpsReport(_ips(), path: '/r/Runner.ips')!;
      expect(r.pid, 35369);
      final text = r.crash.describe();
      expect(
        text,
        startsWith(
          'The app crashed in native code: '
          'EXC_CRASH (SIGABRT) at ',
        ),
      );
      // The throw machinery on top is skipped.
      expect(r.crash.frames, [
        '+[FIRInstallations validateAPIKey:] FIRInstallations.m:162 '
            '(Runner.debug.dylib)',
        r'static AppDelegate.$main() (Runner.debug.dylib)',
      ]);
      expect(text, endsWith('Full report: /r/Runner.ips'));
      expect(r.crash.reportPending, isFalse);
    });

    test('a signal: the crashed thread, and the abort message', () {
      final r = parseIpsReport(
        _ips(
          exceptionBacktrace: false,
          asi: {
            'libswiftCore.dylib': ['Fatal error: Index out of range'],
          },
        ),
      )!;
      expect(r.crash.reason, 'Fatal error: Index out of range');
      expect(r.crash.frames, ['main (Runner.debug.dylib)']);
    });

    test('not a report', () {
      expect(parseIpsReport('{}'), isNull);
      expect(parseIpsReport('{}\n{"bug_type":"288"}'), isNull);
    });
  });

  test('capture time is converted from its offset', () {
    expect(
      parseIpsTime('2026-09-28 09:56:00.8018 +0500')!.toUtc(),
      DateTime.utc(2026, 9, 28, 4, 56, 0, 801, 800),
    );
    expect(parseIpsTime('yesterday'), isNull);
  });

  test('the uncaught exception line from the log', () {
    const log =
        '2026-09-28 09:56:00.790 E  Runner[35369:1a2b] [General] *** '
        "Terminating app due to uncaught exception 'FIRInstallationsInvalid"
        "ArgumentException', reason: 'The API key is not valid.'\n"
        '2026-09-28 09:56:00.791 E  Runner[35369:1a2b] (next line)';
    expect(
      exceptionFromLog(log),
      "*** Terminating app due to uncaught exception "
      "'FIRInstallationsInvalidArgumentException', reason: "
      "'The API key is not valid.'",
    );
    expect(exceptionFromLog('nothing here'), isNull);
  });

  group('parseLogcatCrash', () {
    test('a Kotlin exception of this process', () {
      const log = '''
--------- beginning of crash
09-29 10:00:01.100  4242  4242 E AndroidRuntime: FATAL EXCEPTION: main
09-29 10:00:01.100  4242  4242 E AndroidRuntime: Process: com.example.app, PID: 4242
09-29 10:00:01.100  4242  4242 E AndroidRuntime: java.lang.IllegalStateException: Default FirebaseApp is not initialized
09-29 10:00:01.100  4242  4242 E AndroidRuntime: 	at com.google.firebase.FirebaseApp.getInstance(FirebaseApp.java:179)
09-29 10:00:01.100  4242  4242 E AndroidRuntime: 	at com.example.app.MainActivity.onCreate(MainActivity.kt:12)
09-29 10:00:02.000  5555  5555 E AndroidRuntime: FATAL EXCEPTION: main
''';
      final crash = parseLogcatCrash(log, 4242)!;
      expect(
        crash.reason,
        'java.lang.IllegalStateException: Default FirebaseApp is not '
        'initialized',
      );
      expect(crash.frames, [
        'at com.google.firebase.FirebaseApp.getInstance(FirebaseApp.java:179)',
        'at com.example.app.MainActivity.onCreate(MainActivity.kt:12)',
      ]);
      // Another process's crash is not this app's.
      expect(parseLogcatCrash(log, 7), isNull);
    });

    test('a native signal with its abort message', () {
      const log = '''
09-29 10:00:01.100  4242  4300 F libc    : Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid 4300 (1.raster), pid 4242 (com.example.app)
09-29 10:00:01.300  4400  4400 F DEBUG   : Abort message: 'Check failed: surface'
09-29 10:00:01.300  4400  4400 F DEBUG   :       #00 pc 000000000005b8c4  /apex/com.android.runtime/lib64/bionic/libc.so (abort+164)
09-29 10:00:01.300  4400  4400 F DEBUG   :       #01 pc 0000000001a2b3c4  /data/app/com.example.app/lib/arm64/libflutter.so
''';
      final crash = parseLogcatCrash(log, 4242)!;
      expect(crash.kind, 'Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE)');
      expect(crash.reason, "Abort message: 'Check failed: surface'");
      expect(crash.frames, hasLength(2));
      expect(crash.frames.first, startsWith('#00 pc '));
    });
  });

  test('a crash known only from the log says the report is coming', () {
    final text = NativeCrash(
      reason: "*** Terminating app due to uncaught exception 'X', reason: 'y'",
      reportPending: true,
    ).describe();
    expect(text, startsWith('The app crashed in native code.\n*** '));
    expect(text, contains('still writing the crash report'));
  });

  test(
    'a process that did not crash: callers wait for the first looks only',
    () async {
      final watch = NativeCrashWatch(
        CrashTarget(pid: pid, operatingSystem: 'macos', since: DateTime.now()),
        crashLogWait: const Duration(seconds: 20),
      );
      final sw = Stopwatch()..start();
      expect(await watch.current(wait: const Duration(seconds: 15)), isNull);
      // Three looks at the log, not the whole 20 s window.
      expect(sw.elapsed, lessThan(const Duration(seconds: 14)));
    },
    testOn: 'mac-os',
  );
}
