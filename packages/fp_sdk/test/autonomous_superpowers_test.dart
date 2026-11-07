import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fp_sdk/fp_sdk.dart';

void main() {
  group('Autonomous Superpowers SDK Suite', () {
    testWidgets('RebuildProfiler tracks widget rebuild counts and identifies hot rebuilders',
        (tester) async {
      RebuildProfiler.initialize();
      RebuildProfiler.reset();

      int count = 0;
      late StateSetter outerSetState;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              outerSetState = setState;
              return Scaffold(
                body: Column(
                  children: [
                    Text('Count: $count'),
                    ElevatedButton(
                      key: const Key('btn'),
                      onPressed: () {
                        setState(() {
                          count++;
                        });
                      },
                      child: const Text('Increment'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      // Rebuild 5 times
      for (var i = 0; i < 5; i++) {
        outerSetState(() {
          count++;
        });
        await tester.pump();
      }

      final stats = RebuildProfiler.getStats();
      expect(stats['totalRebuilds'], greaterThanOrEqualTo(5));
      expect(stats['distinctWidgetCount'], greaterThan(0));

      final counts = stats['rebuildCounts'] as List;
      expect(counts, isNotEmpty);
      expect(counts.any((e) => e['widget'].toString().contains('Text')), isTrue);
    });

    testWidgets('DesignTokenAuditor flags unthemed colors and off-grid border radii',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          ),
          home: Scaffold(
            body: Column(
              children: [
                // Hardcoded raw color not in colorScheme
                Text(
                  'Unthemed Text',
                  style: TextStyle(color: const Color(0xFFE53935)),
                ),
                // Off-grid border radius (7.0 dp)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3),
                    borderRadius: BorderRadius.circular(7.0),
                  ),
                  child: const SizedBox(width: 50, height: 50),
                ),
              ],
            ),
          ),
        ),
      );

      final audit = DesignTokenAuditor.audit();
      expect(audit['unthemedColorCount'], greaterThanOrEqualTo(1));
      expect(audit['offGridBorderRadiiCount'], greaterThanOrEqualTo(1));
      expect(audit['tokenComplianceScore'], lessThan(100));

      final offGrid = audit['offGridBorderRadii'] as List;
      expect(offGrid.any((e) => e['radius'] == 7.0), isTrue);
      expect(offGrid.first['suggestedRadius'], 8.0);

      final unthemed = audit['unthemedColors'] as List;
      expect(unthemed.any((e) => e['suggestedToken'] != null), isTrue);
    });

    testWidgets('AppCrawler gathers candidates and evaluates screen health',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Home Screen')),
            body: ListView(
              children: [
                ListTile(
                  key: const Key('settings_tile'),
                  title: const Text('Settings'),
                  onTap: () {},
                ),
                ElevatedButton(
                  key: const Key('delete_btn'),
                  onPressed: () {},
                  child: const Text('Delete Account'),
                ),
              ],
            ),
          ),
        ),
      );

      final crawl = AppCrawler.inspectScreenForCrawl();
      expect(crawl['navigableCandidateCount'], greaterThan(0));

      final candidates = crawl['navigableCandidates'] as List;
      // Should find Settings ListTile
      expect(candidates.any((c) => c['label'].toString().contains('Settings')), isTrue);
      // Should filter out destructive Delete button
      expect(candidates.any((c) => c['label'].toString().toLowerCase().contains('delete')), isFalse);
    });
  });
}
