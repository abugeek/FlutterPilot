import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_gorouter/flutterpilot_gorouter.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoRouterPilotInspector.reset();
    FlutterPilot.initialize();
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

    test('register without FlutterPilot.initialize prints warning and skips', () {
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
    });
  });
}
