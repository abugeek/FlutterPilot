import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/diagnostic_payload.dart';

void main() {
  test('sanitizes deeply nested and oversized diagnostic values', () {
    final value = <String, dynamic>{
      'message': 'x' * 5000,
      'nested': {
        'a': {
          'b': {
            'c': {
              'd': {
                'e': {
                  'f': {
                    'g': {'h': 'too deep'},
                  },
                },
              },
            },
          },
        },
      },
    };

    final result = DiagnosticPayload.boundedMap(value);
    expect(result['message'], contains('<truncated>'));
    expect(result.toString().length, lessThan(10000));
  });

  test('bounds large map payloads to a compact marker', () {
    final value = <String, dynamic>{
      for (var i = 0; i < 1000; i++) 'key_$i': 'value' * 100,
    };
    final result = DiagnosticPayload.boundedMap(value);
    expect(result['<truncated>'], isTrue);
  });
}
