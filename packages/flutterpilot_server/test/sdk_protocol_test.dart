import 'dart:io';

import 'package:flutterpilot_server/src/sdk_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('the SDK in this repo carries the same number as the server', () {
    final sdk = File(
      '../flutterpilot_sdk/lib/flutterpilot_sdk.dart',
    ).readAsStringSync();
    final declared = RegExp(
      r'static const protocol = (\d+);',
    ).firstMatch(sdk)?.group(1);
    expect(declared, '$sdkProtocol');
  });

  test('every protocol since the first says what it added', () {
    for (var v = 2; v <= sdkProtocol; v++) {
      expect(protocolAdds, contains(v));
    }
  });

  test('the same number says nothing', () {
    expect(protocolNote(sdkProtocol), isNull);
  });

  test('an older app SDK is told what it lacks and how to update', () {
    final note = protocolNote(1, server: 2)!;
    expect(note, contains('older than this server (protocol 1, server 2)'));
    expect(note, contains('the screen after wait_for and navigate_to'));
    expect(note, contains('pubspec.yaml'));
  });

  test('a newer app SDK says to rebuild the server', () {
    final note = protocolNote(3, server: 2)!;
    expect(note, contains('newer than this server'));
    expect(note, contains('flutterpilot mcp install'));
  });
}
