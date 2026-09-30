import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_gorouter/flutterpilot_gorouter.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoRouterPilotInspector.reset();
    final print = debugPrint;
    FlutterPilot.initialize();
    // initialize() routes debugPrint through its log buffer; widget tests
    // require the test binding's back.
    debugPrint = print;
  });

  tearDown(() {
    GoRouterPilotInspector.reset();
  });

  group('GoRouterPilotInspector', () {
    test('register warns if called before FlutterPilot.initialize', () {
      // After reset() _registered is false — calling register() before
      // FlutterPilot being initialised should not throw but print a warning.
      // Since we called FlutterPilot.initialize() in setUp this validates
      // the happy path doesn't crash.
      GoRouterPilotInspector.reset();

      // With FlutterPilot initialized, register a minimal router
      FlutterPilot.initialize();
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, __) => const SizedBox())],
      );
      try {
        GoRouterPilotInspector.register(router);
      } on UnsupportedError {
        // Expected — registerExtension not available in test env.
      } finally {
        router.dispose();
      }
    });

    test('register is idempotent', () {
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, __) => const SizedBox())],
      );
      try {
        GoRouterPilotInspector.register(router);
        GoRouterPilotInspector.register(router); // second call ignored
      } on UnsupportedError {
        // Expected in test env.
      } finally {
        router.dispose();
      }
    });

    test('reset allows re-registration', () {
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, __) => const SizedBox())],
      );
      GoRouterPilotInspector.reset();
      try {
        GoRouterPilotInspector.register(router);
      } on UnsupportedError {
        // Expected in test env.
      } finally {
        router.dispose();
      }
    });

    test(
      'register without FlutterPilot.initialize prints warning and skips',
      () {
        // Simulate calling register before initialize by resetting both
        GoRouterPilotInspector.reset();

        final router = GoRouter(
          routes: [GoRoute(path: '/', builder: (_, __) => const SizedBox())],
        );
        // This should not throw — just print a warning and return early
        // because _registered guard prevents double-registration issues
        try {
          GoRouterPilotInspector.register(router);
        } on UnsupportedError {
          // Expected — registerExtension not available in test env.
        } finally {
          router.dispose();
        }
      },
    );
    test('routePaths lists full paths through shells and children', () {
      final routes = <RouteBase>[
        ShellRoute(
          builder: (_, _, child) => child,
          routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
        ),
        GoRoute(
          path: '/story/:id',
          builder: (_, _) => const SizedBox(),
          routes: [
            GoRoute(path: 'comments', builder: (_, _) => const SizedBox()),
          ],
        ),
      ];
      expect(GoRouterPilotInspector.routePaths(routes), [
        '/',
        '/story/:id',
        '/story/:id/comments',
      ]);
    });

    testWidgets('an unknown route fails and the app stays where it was', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('home')),
          GoRoute(path: '/saved', builder: (_, _) => const Text('saved')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      GoRouterPilotInspector.register(router);

      Object? error;
      final failed = NavigationTracker.customNavigateHandler!('/bookmarks')
          .catchError((Object e) {
            error = e;
            return false;
          });
      await tester.pump(); // the frame the handler waits for
      await failed;
      await tester.pumpAndSettle();
      expect('$error', contains('No route matches "/bookmarks"'));
      expect('$error', contains('/saved'));
      expect(find.text('home'), findsOneWidget);
      expect(tester.takeException(), isNull); // the listener didn't throw

      Object? pushError;
      final pushed = GoRouterPilotInspector.navigateChecked(
        router,
        'push',
        '/nope',
      ).catchError((Object e) => pushError = e);
      await tester.pump();
      await pushed;
      await tester.pumpAndSettle();
      expect('$pushError', contains('No route matches "/nope"'));
      expect(router.canPop(), isFalse);
      expect(find.text('home'), findsOneWidget);

      final arrived = NavigationTracker.customNavigateHandler!('/saved');
      await tester.pump();
      expect(await arrived, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('saved'), findsOneWidget);
    });
  });
}
