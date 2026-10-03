import 'package:flutterpilot_server/src/reload_failure.dart';
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

  test('anything else keeps the compile-error hint', () {
    final text = reloadFailureText(
      'reloadSources',
      "lib/main.dart:12:3: Error: Expected ';' after this.",
    );

    expect(text, contains("Expected ';' after this."));
    expect(text, contains('usually a compile error'));
    expect(text, isNot(contains('App Management')));
  });
}
