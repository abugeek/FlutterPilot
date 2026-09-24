import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  group('UiHealthAuditor & Design Quality Auditor Tests', () {
    testWidgets('flags action buttons containing multi-line card content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              key: const Key('bad_button'),
              onPressed: () {},
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Card Title', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Card subtitle description of feature', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );

      final audit = UiHealthAuditor.audit();
      expect(audit['isHealthy'], isFalse);
      expect(audit['designScore'], lessThan(100));

      final designIssues = (audit['designIssues'] as List).cast<Map<String, dynamic>>();
      expect(
        designIssues.any((d) => d['category'] == 'component_role_mismatch'),
        isTrue,
      );
      final issue = designIssues.firstWhere((d) => d['category'] == 'component_role_mismatch');
      expect(issue['target'], contains('bad_button'));
      expect(issue['recommendation'], contains('Card'));
    });

    testWidgets('flags micro-typography below 11sp', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text(
              'Tiny unreadable text',
              style: TextStyle(fontSize: 9.0),
            ),
          ),
        ),
      );

      final audit = UiHealthAuditor.audit();
      final designIssues = (audit['designIssues'] as List).cast<Map<String, dynamic>>();
      expect(
        designIssues.any((d) => d['category'] == 'typography_legibility'),
        isTrue,
      );
      final issue = designIssues.firstWhere((d) => d['category'] == 'typography_legibility');
      expect(issue['message'], contains('9.0sp'));
    });

    testWidgets('flags rigid fixed child widths in Wrap layout', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(width: 150, height: 80, child: Container(color: Colors.red)),
                    SizedBox(width: 150, height: 80, child: Container(color: Colors.blue)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final audit = UiHealthAuditor.audit();
      final designIssues = (audit['designIssues'] as List).cast<Map<String, dynamic>>();
      expect(
        designIssues.any((d) => d['category'] == 'rigid_child_sizing'),
        isTrue,
      );
      final issue = designIssues.firstWhere((d) => d['category'] == 'rigid_child_sizing');
      expect(issue['message'], contains('hardcoded fixed widths inside a Wrap'));
    });

    testWidgets('awards 100/100 A+ for pristine, responsive, well-structured UI', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Clean Screen')),
            body: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(16),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: List.generate(4, (i) {
                return Card(
                  child: InkWell(
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.star),
                          const SizedBox(height: 8),
                          Text('Tile $i', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text('Subtitle description', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      );

      final audit = UiHealthAuditor.audit();
      expect(audit['isHealthy'], isTrue);
      expect(audit['designScore'], equals(100));
      expect(audit['designGrade'], contains('A+'));
      expect(audit['designIssueCount'], equals(0));
      expect(audit['overflowCount'], equals(0));
    });
  });
}
