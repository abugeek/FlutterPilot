import 'package:fp_server/src/reload_failure.dart';
import 'package:test/test.dart';

void main() {
  // Field test (Octana, macOS 27): flutter_tools could not copy the kernel
  // into the sandboxed app's container, and the reply was 20 stack frames
  // plus "usually a compile error".
  test('a blocked write into a sandboxed macOS app is named as that', () {
    final text = reloadFailureText(
      'reloadSources',
      'Error: Flutter failed to create file at '
          '"/Users/me/Library/Containers/com.example.app/Data/tmp/app1/app/main.dart.incremental.dill".\n'
          'Please ensure that the SDK and/or project is installed in a location that has read/write permissions for the current user.\n'
          ' #0      throwToolExit (package:flutter_tools/src/base/common.dart:34:3)\n'
          '#1      _throwFileSystemException (package:flutter_tools/src/base/error_handling_io.dart:1502:3)\n'
          '<asynchronous suspension>\n'
          '#11     FlutterDevice.updateDevFS (package:flutter_tools/src/resident_runner.dart:506:16)',
    );

    expect(text, startsWith('reloadSources failed: Error: Flutter failed'));
    expect(text, contains('main.dart.incremental.dill'));
    expect(text, isNot(contains('throwToolExit')));
    expect(text, isNot(contains('asynchronous suspension')));
    expect(text, contains('not a compile error'));
    expect(text, contains('App Management'));
  });

  test('a permission denied write into a sandboxed macOS container is detected', () {
    final text = reloadFailureText(
      'reloadSources',
      'FileSystemException: An error occurred while writing to /Users/me/Library/Containers/com.example.app/Data/tmp/kernel.dill: Operation not permitted',
    );
    expect(text, contains('not a compile error'));
    expect(text, contains('DebugProfile.entitlements'));
    expect(text, contains('App Management'));
  });

  // Field test (Octana): carousel SVGs deleted while the app ran.
  test('a missing asset is named as that', () {
    final text = reloadFailureText(
      'hotRestart',
      'Error: Flutter failed to copy /app/assets/flow/welcome_4.svg to '
          '/Users/me/Library/Containers/com.example.app/Data/tmp/app1/app/build/flutter_assets/assets/flow/welcome_4.svg '
          'due to source location error. The file or directory could not be found.\n'
          "PathNotFoundException: Cannot open file, path = '/app/assets/flow/welcome_4.svg'",
    );

    expect(text, contains('welcome_4.svg'));
    expect(text, contains('not a compile error'));
    expect(text, contains('pubspec.yaml'));
    expect(text, isNot(contains('App Management')));
  });

  test('anything else keeps the compile-error hint', () {
    final text = reloadFailureText(
      'reloadSources',
      "lib/main.dart:12:3: Error: Expected ';' after this.",
    );

    expect(text, contains("Expected ';' after this."));
    expect(text, contains('usually a compile error'));
    expect(text, isNot(contains('App Management')));
  });

  // flutter_tools answers a reload that does not compile with an empty
  // message and prints the compiler's errors in its own terminal.
  test('compiler errors are read from flutter run output', () {
    final errors = compileErrorsIn(
      'Performing hot reload...                                        \n'
      "lib/screens.dart:44:23: Error: Expected ',' before this.\n"
      "                      Filter.open => 'Open',\n"
      '                      ^^^^^^\n'
      'Performing hot restart...                                       \n'
      "lib/screens.dart:44:23: Error: Expected ',' before this.\n"
      "                      Filter.open => 'Open',\n"
      '                      ^^^^^^\n'
      'Restarted application in 90ms.\n',
    );
    expect(
      errors,
      "lib/screens.dart:44:23: Error: Expected ',' before this.\n"
      "                      Filter.open => 'Open',\n"
      '                      ^^^^^^',
    );
    expect(compileErrorsIn('Reloaded 1 of 900 libraries in 300ms.'), isEmpty);
  });

  test('with compiler errors the reply is the errors', () {
    final text = reloadFailureText(
      'reloadSources',
      '',
      compileErrors: "lib/a.dart:1:1: Error: Expected ';' after this.",
    );
    expect(text, contains('does not compile'));
    expect(text, contains("lib/a.dart:1:1: Error: Expected ';'"));
    expect(text, contains('still running the code from before'));
    expect(text, isNot(contains('usually a compile error')));
  });

  test('analyzer output keeps the errors, with paths from the app folder', () {
    final errors = analyzerErrorsIn(
      'INFO|LINT|PREFER_CONST|/app/lib/a.dart|3|5|4|Use const.\n'
          "ERROR|SYNTACTIC_ERROR|EXPECTED_TOKEN|/app/lib/screens.dart|44|23|6|Expected to find ','.\n"
          'WARNING|STATIC_WARNING|UNUSED|/app/lib/b.dart|1|1|1|Unused.\n',
      '/app',
    );
    expect(errors, "lib/screens.dart:44:23: Expected to find ','.");
  });

  test('only a failure without a cause of its own looks for them', () {
    expect(mayBeCompileError(''), isTrue);
    expect(mayBeCompileError('Flutter failed to copy a.svg to b.svg'), isFalse);
  });

  test('the app folder is the one with the pubspec above the entrypoint', () {
    bool exists(String path) => path == '/work/app/pubspec.yaml';
    expect(
      projectRootOfFile('/work/app/tool/pilot_main.dart', exists: exists),
      '/work/app',
    );
    expect(
      projectRootOfFile('/work/app/lib/src/main.dart', exists: exists),
      '/work/app',
    );
    expect(projectRootOfFile('/elsewhere/main.dart', exists: exists), isNull);
  });

  // A Windows app: the analyzer prints `D:\app\lib\a.dart`, the entrypoint URI
  // is `file:///D:/app/lib/main.dart`, and both have to come out as app
  // folders named with forward slashes (field tests #341, #342).
  test('a Windows analyzer path loses the app folder, backslashes and all', () {
    final errors = analyzerErrorsIn(
      r'ERROR|SYNTACTIC_ERROR|EXPECTED_TOKEN|D:\app\lib\screens.dart|44|23|6|Expected to find ",".'
          '\n',
      r'D:\app',
    );
    expect(errors, 'lib/screens.dart:44:23: Expected to find ",".');
  });

  test('a Windows entrypoint walks up its own separator', () {
    bool exists(String path) => path == 'D:/app/pubspec.yaml';
    expect(
      projectRootOfFile(r'D:\app\tool\pilot_main.dart', exists: exists),
      'D:/app',
    );
    // The server composes `$root/$name` from it, so forward slashes matter.
    expect(
      projectRootOfFile(r'D:\app\lib\src\main.dart', exists: exists),
      'D:/app',
    );
    expect(
      projectRootOfFile(r'D:\elsewhere\main.dart', exists: exists),
      isNull,
    );
  });
}
