import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    final print = debugPrint;
    FlutterPilot.initialize();
    // initialize() routes debugPrint through its log buffer; widget tests
    // require the test binding's back.
    debugPrint = print;
  });

  Future<Map<String, dynamic>> swipe(
    WidgetTester tester,
    Map<String, String> params,
  ) async {
    ServiceExtensionResponse? response;
    FlutterPilot.debugCallExtension(
      'ext.flutterpilot.swipeWidget',
      params,
    ).then((r) => response = r);
    for (var i = 0; i < 500 && response == null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    return json.decode(response!.result!) as Map<String, dynamic>;
  }

  // Apple's bouncing physics overscrolls less the further it goes: a
  // 300 px swipe in 20 moves never armed the indicator on macOS.
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('a swipe down pulls to refresh (${platform.name})', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      var refreshed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefreshIndicator(
              onRefresh: () async => refreshed++,
              child: ListView(
                children: [
                  for (var i = 0; i < 30; i++)
                    ListTile(key: Key('item_$i'), title: Text('Item $i')),
                ],
              ),
            ),
          ),
        ),
      );
      final result = await swipe(tester, {
        'key': 'item_1',
        'direction': 'down',
        'distance': '300',
      });
      debugDefaultTargetPlatformOverride = null;
      expect(result['pullToRefresh'], isTrue);
      expect(refreshed, 1);
    });
  }

  testWidgets('a swipe down in a scrolled list only scrolls it', (
    tester,
  ) async {
    var refreshed = 0;
    final controller = ScrollController(initialScrollOffset: 400);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RefreshIndicator(
            onRefresh: () async => refreshed++,
            child: ListView(
              controller: controller,
              children: [
                for (var i = 0; i < 30; i++)
                  ListTile(key: Key('item_$i'), title: Text('Item $i')),
              ],
            ),
          ),
        ),
      ),
    );
    final result = await swipe(tester, {
      'key': 'item_10',
      'direction': 'down',
      'distance': '100',
    });
    expect(result.containsKey('pullToRefresh'), isFalse);
    expect(refreshed, 0);
    expect(controller.offset, lessThan(400));
  });
}
