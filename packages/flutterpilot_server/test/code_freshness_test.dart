import 'dart:io';

import 'package:flutterpilot_server/src/code_freshness.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('fp_fresh_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String path, DateTime at) => File('${tmp.path}/$path')
    ..createSync(recursive: true)
    ..setLastModifiedSync(at);

  final started = DateTime(2026, 10, 11, 9);

  test('an app that runs what is on disk has nothing to say', () {
    write('lib/main.dart', started.subtract(const Duration(minutes: 5)));
    write('pubspec.lock', started.subtract(const Duration(minutes: 5)));
    final fresh = codeFreshness(
      tmp.path,
      codeLoaded: started,
      appStarted: started,
    );
    expect(fresh.fresh, isTrue);
    expect(fresh.note(hotReload: true), isNull);
  });

  test('Dart files edited after the last reload are named', () {
    write('lib/main.dart', started.subtract(const Duration(minutes: 5)));
    write('lib/a.dart', started.add(const Duration(minutes: 1)));
    write('lib/src/b.dart', started.add(const Duration(minutes: 2)));
    final stale = codeFreshness(
      tmp.path,
      codeLoaded: started,
      appStarted: started,
    );
    expect(stale.dart, ['lib/src/b.dart', 'lib/a.dart']);
    final note = stale.note(hotReload: true)!;
    expect(note, contains('2 Dart files (lib/src/b.dart, lib/a.dart)'));
    expect(note, contains('hot_reload'));
    expect(
      stale.note(hotReload: false),
      contains('profile build cannot hot reload'),
    );
  });

  test('a reload since the edit makes it fresh again', () {
    write('lib/a.dart', started.add(const Duration(minutes: 1)));
    final fresh = codeFreshness(
      tmp.path,
      codeLoaded: started.add(const Duration(minutes: 3)),
      appStarted: started,
    );
    expect(fresh.fresh, isTrue);
  });

  test('a changed pubspec.lock needs a new build, whatever was reloaded', () {
    write('pubspec.lock', started.add(const Duration(minutes: 1)));
    write('lib/a.dart', started.add(const Duration(minutes: 1)));
    final stale = codeFreshness(
      tmp.path,
      codeLoaded: started.add(const Duration(minutes: 3)),
      appStarted: started,
    );
    expect(stale.relaunch, ['pubspec.lock']);
    final note = stale.note(hotReload: true)!;
    expect(note, contains('pubspec.lock changed since the app was built'));
    expect(note, contains('launch_app(relaunch: true)'));
  });

  test('many files are counted, three are named', () {
    for (var i = 0; i < 6; i++) {
      write('lib/f$i.dart', started.add(Duration(minutes: i + 1)));
    }
    final note = codeFreshness(
      tmp.path,
      codeLoaded: started,
      appStarted: started,
    ).note(hotReload: true)!;
    expect(
      note,
      contains('6 Dart files (lib/f5.dart, lib/f4.dart, lib/f3.dart, +3)'),
    );
  });
}
