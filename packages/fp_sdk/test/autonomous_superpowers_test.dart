import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fp_sdk/fp_sdk.dart';
import 'package:fp_sdk/src/source_locator.dart';

void main() {
  // As the SDK does with the folder the server sends: it is what tells the
  // app's widgets from the framework's.
  setUp(() {
    // ignore: invalid_use_of_protected_member
    WidgetInspectorService.instance.addPubRootDirectories([
      pubRootFor(Directory.current.path),
    ]);
  });

  testWidgets('RebuildProfiler counts rebuilds of app widgets only', (
    tester,
  ) async {
    addTearDown(RebuildProfiler.dispose);
    expect(RebuildProfiler.getStats()['started'], isTrue);
    var count = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(
              body: Column(
                children: [
                  Text('Count: $count'),
                  ElevatedButton(onPressed: () {}, child: const Text('Go')),
                ],
              ),
            );
          },
        ),
      ),
    );
    RebuildProfiler.reset();
    for (var i = 0; i < 5; i++) {
      rebuild(() => count++);
      await tester.pump();
    }
    final rows = (RebuildProfiler.getStats()['rebuilds'] as List).cast<Map>();
    final text = rows.firstWhere((r) => r['widget'] == 'Text');
    expect(text['rebuilds'], 5); // the const Text('Go') never rebuilds
    expect(text['createdAt'], contains('autonomous_superpowers_test.dart'));
    // The button's own internals (InkWell, Material…) are not app code.
    expect(rows.any((r) => r['widget'] == 'InkWell'), isFalse);
  });

  testWidgets('DesignTokenAuditor flags app colors and radii, not the '
      "framework's", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.blue),
        home: Scaffold(
          body: Column(
            children: [
              const Text('Raw', style: TextStyle(color: Color(0xFFE53935))),
              Builder(
                builder: (context) => Text(
                  'Token',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .5),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const SizedBox(width: 50, height: 50),
              ),
              // The framework colors the hint itself: not the app's to fix.
              const TextField(decoration: InputDecoration(hintText: 'Hint')),
            ],
          ),
        ),
      ),
    );
    final audit = DesignTokenAuditor.audit();
    final colors = (audit['unthemedColors'] as List).cast<Map>();
    expect(colors.map((c) => c['color']), ['#FFE53935']);
    expect(colors.single['location'], contains('autonomous_superpowers'));
    final radii = (audit['offGridRadii'] as List).cast<Map>();
    expect(radii.single['radius'], 7.0);
    expect(radii.single['nearest'], 8);
  });

  testWidgets('AppCrawler offers rows, never buttons or action rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(title: const Text('Settings'), onTap: () {}),
              ListTile(title: const Text('Delete account'), onTap: () {}),
              ElevatedButton(onPressed: () {}, child: const Text('Profile')),
            ],
          ),
        ),
      ),
    );
    final labels = [
      for (final c
          in AppCrawler.inspectScreenForCrawl()['navigableCandidates'] as List)
        c['label'],
    ];
    expect(labels, ['Settings']);
  });

  testWidgets('spacing audit reports app padding with its source', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Padding(padding: EdgeInsets.all(13), child: Text('A')),
              const Padding(padding: EdgeInsets.all(16), child: Text('B')),
              Container(
                padding: const EdgeInsets.all(6),
                child: const Text('C'),
              ),
              // A chip pads itself by 1: framework, not reported.
              const Chip(label: Text('chip')),
            ],
          ),
        ),
      ),
    );
    final report = UiHealthAuditor.audit(designQuality: true);
    final issues = (report['spacingGridIssues'] as List).cast<Map>();
    expect(issues.map((i) => i['widget']), ['Padding', 'Container']);
    expect(issues.first['details'], contains('padding 13'));
    expect(issues.first['source'], contains('autonomous_superpowers'));
  });
}
