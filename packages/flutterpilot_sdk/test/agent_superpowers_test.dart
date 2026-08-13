import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  group('Agent Superpowers Tests', () {
    testWidgets('UiHealthAuditor detects small touch targets (<48x48)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: IconButton(
                    key: const ValueKey('tiny_button'),
                    icon: const Icon(Icons.close),
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final audit = UiHealthAuditor.audit();
      expect(audit['accessibilityIssueCount'], greaterThanOrEqualTo(1));
      expect(audit['isHealthy'], isFalse);
      final issues = audit['accessibilityIssues'] as List;
      expect(issues.any((i) => i['target'].toString().contains('tiny_button')), isTrue);
    });

    testWidgets('UiHealthAuditor reports healthy on standard Material layout', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('standard_button'),
                onPressed: () {},
                child: const Text('Submit'),
              ),
            ),
          ),
        ),
      );

      final audit = UiHealthAuditor.audit();
      expect(audit['overflowCount'], equals(0));
    });

    test('SimpleGifEncoder encodes valid GIF89a header and structure', () {
      final frame1 = Uint8List.fromList(List.generate(100, (i) => i % 256));
      final frame2 = Uint8List.fromList(List.generate(100, (i) => (i * 2) % 256));

      final gifBytes = SimpleGifEncoder.encode(
        width: 10,
        height: 10,
        frames: [frame1, frame2],
        delayMs: 200,
      );

      expect(gifBytes.length, greaterThan(20));
      // First 6 bytes must be 'GIF89a'
      final header = ascii.decode(gifBytes.sublist(0, 6));
      expect(header, equals('GIF89a'));
      // Last byte must be 0x3B (trailer)
      expect(gifBytes.last, equals(0x3B));
    });
  });
}
