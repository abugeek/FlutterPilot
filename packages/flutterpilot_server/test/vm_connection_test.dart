import 'dart:io';

import 'package:test/test.dart';

/// vm_service's default keep-alive (15 s ping, closed when no pong comes
/// within another 15 s) dropped the connection to an app that was only slow:
/// field test #293. Every connection is made by `connectVmService`, which
/// turns it off.
void main() {
  test('the server connects to the VM service without the keep-alive', () {
    final calls = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          for (final match in RegExp(
            r'vmServiceConnectUri\([^;]*;',
          ).allMatches(file.readAsStringSync()))
            match.group(0)!,
    ];
    expect(calls, hasLength(1));
    expect(calls.single, contains('pingInterval: null'));
  });
}
