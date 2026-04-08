import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/navigation_tracker.dart';

void main() {
  group('NavigationTracker edge cases', () {
    setUp(() {
      NavigationTracker.reset();
    });

    test('didRemove handles duplicate route names correctly', () {
      final tracker = NavigationTracker();

      final route1 = MaterialPageRoute(
        settings: const RouteSettings(name: '/list'),
        builder: (_) => Container(),
      );
      final route2 = MaterialPageRoute(
        settings: const RouteSettings(name: '/list'),
        builder: (_) => Container(),
      );
      final route3 = MaterialPageRoute(
        settings: const RouteSettings(name: '/detail'),
        builder: (_) => Container(),
      );

      tracker.didPush(route1, null);
      tracker.didPush(route2, route1);
      tracker.didPush(route3, route2);

      expect(NavigationTracker.stack, ['/list', '/list', '/detail']);

      // Remove should use lastIndexOf — removes the second /list, not the first
      tracker.didRemove(route2, route1);
      expect(NavigationTracker.stack, ['/list', '/detail']);
    });

    test('didReplace replaces route correctly', () {
      final tracker = NavigationTracker();

      final homeRoute = MaterialPageRoute(
        settings: const RouteSettings(name: '/home'),
        builder: (_) => Container(),
      );
      final oldRoute = MaterialPageRoute(
        settings: const RouteSettings(name: '/old'),
        builder: (_) => Container(),
      );
      final newRoute = MaterialPageRoute(
        settings: const RouteSettings(name: '/new'),
        builder: (_) => Container(),
      );

      tracker.didPush(homeRoute, null);
      tracker.didPush(oldRoute, homeRoute);

      expect(NavigationTracker.stack, ['/home', '/old']);

      tracker.didReplace(newRoute: newRoute, oldRoute: oldRoute);
      expect(NavigationTracker.stack, ['/home', '/new']);
    });

    test('didReplace fires onStateChange callback', () {
      String? capturedName;
      dynamic capturedValue;
      NavigationTracker.onStateChange = (source, name, value) {
        capturedName = name;
        capturedValue = value;
      };

      final tracker = NavigationTracker();
      final oldRoute = MaterialPageRoute(
        settings: const RouteSettings(name: '/old'),
        builder: (_) => Container(),
      );
      final newRoute = MaterialPageRoute(
        settings: const RouteSettings(name: '/replaced'),
        builder: (_) => Container(),
      );

      tracker.didPush(oldRoute, null);
      tracker.didReplace(newRoute: newRoute, oldRoute: oldRoute);

      expect(capturedName, 'replace');
      expect(capturedValue, '/replaced');
    });

    test('handles routes with null names', () {
      final tracker = NavigationTracker();

      final nullRoute = MaterialPageRoute(
        settings: const RouteSettings(name: null),
        builder: (_) => Container(),
      );

      tracker.didPush(nullRoute, null);
      expect(NavigationTracker.stack, [null]);
      expect(NavigationTracker.currentRoute, 'Unknown');
    });

    test('pop on empty stack does not throw', () {
      final tracker = NavigationTracker();

      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/gone'),
        builder: (_) => Container(),
      );

      // Pop on empty stack — should be safe
      expect(() => tracker.didPop(route, null), returnsNormally);
      expect(NavigationTracker.stack, isEmpty);
    });

    test('didRemove with non-existent route does not throw', () {
      final tracker = NavigationTracker();

      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/never-pushed'),
        builder: (_) => Container(),
      );

      expect(() => tracker.didRemove(route, null), returnsNormally);
    });

    test('stack is unmodifiable', () {
      final tracker = NavigationTracker();
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/immutable'),
        builder: (_) => Container(),
      );

      tracker.didPush(route, null);

      expect(
        () => NavigationTracker.stack.add('/hacked'),
        throwsUnsupportedError,
      );
    });

    test('reset clears onStateChange callback', () {
      NavigationTracker.onStateChange = (_, __, ___) {};
      NavigationTracker.reset();

      // After reset, the callback should be null
      // Push should not throw even though callback was cleared
      final tracker = NavigationTracker();
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: '/after-reset'),
        builder: (_) => Container(),
      );

      expect(() => tracker.didPush(route, null), returnsNormally);
    });

    test('multiple trackers share static state', () {
      final tracker1 = NavigationTracker();
      final tracker2 = NavigationTracker();

      final route1 = MaterialPageRoute(
        settings: const RouteSettings(name: '/from-tracker1'),
        builder: (_) => Container(),
      );
      final route2 = MaterialPageRoute(
        settings: const RouteSettings(name: '/from-tracker2'),
        builder: (_) => Container(),
      );

      tracker1.didPush(route1, null);
      tracker2.didPush(route2, route1);

      expect(NavigationTracker.stack, ['/from-tracker1', '/from-tracker2']);
      expect(NavigationTracker.currentRoute, '/from-tracker2');
    });

    test('deep stack operations', () {
      final tracker = NavigationTracker();
      final routes = <MaterialPageRoute>[];

      for (var i = 0; i < 20; i++) {
        final route = MaterialPageRoute(
          settings: RouteSettings(name: '/screen-$i'),
          builder: (_) => Container(),
        );
        routes.add(route);
        tracker.didPush(route, i > 0 ? routes[i - 1] : null);
      }

      expect(NavigationTracker.stack.length, 20);
      expect(NavigationTracker.currentRoute, '/screen-19');

      // Pop back 5 screens
      for (var i = 19; i >= 15; i--) {
        tracker.didPop(routes[i], routes[i - 1]);
      }

      expect(NavigationTracker.stack.length, 15);
      expect(NavigationTracker.currentRoute, '/screen-14');
    });
  });
}
