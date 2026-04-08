import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/navigation_tracker.dart';

void main() {
  group('NavigationTracker', () {
    setUp(() {
      NavigationTracker.reset();
    });

    test('initially has an empty stack', () {
      expect(NavigationTracker.stack, isEmpty);
      expect(NavigationTracker.currentRoute, 'Unknown');
    });

    test('updates stack on push', () {
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/home'),
        builder: (_) => Container(),
      );

      NavigationTracker().didPush(route, null);

      expect(NavigationTracker.stack, ['/home']);
      expect(NavigationTracker.currentRoute, '/home');
    });

    test('updates stack on pop', () {
      final homeRoute = MaterialPageRoute(
        settings: const RouteSettings(name: '/home'),
        builder: (_) => Container(),
      );
      final detailsRoute = MaterialPageRoute(
        settings: const RouteSettings(name: '/details'),
        builder: (_) => Container(),
      );

      final tracker = NavigationTracker();
      tracker.didPush(homeRoute, null);
      tracker.didPush(detailsRoute, homeRoute);
      expect(NavigationTracker.stack, ['/home', '/details']);

      tracker.didPop(detailsRoute, homeRoute);
      expect(NavigationTracker.stack, ['/home']);
    });

    test('triggers onStateChange callback', () {
      String? caughtSource;
      String? caughtName;
      dynamic caughtValue;

      NavigationTracker.onStateChange = (source, name, value) {
        caughtSource = source;
        caughtName = name;
        caughtValue = value;
      };

      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/settings'),
        builder: (_) => Container(),
      );

      NavigationTracker().didPush(route, null);

      expect(caughtSource, 'navigation');
      expect(caughtName, 'push');
      expect(caughtValue, '/settings');
    });
  });
}
