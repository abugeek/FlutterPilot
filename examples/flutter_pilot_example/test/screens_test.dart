import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_pilot_example/src/screens/dashboard_screen.dart';
import 'package:flutter_pilot_example/src/screens/state_injection_screen.dart';
import 'package:flutter_pilot_example/src/screens/chaos_screen.dart';
import 'package:flutter_pilot_example/src/state/bloc_state.dart';

/// Widget tests for the example app screens.
///
/// These validate that:
/// 1. All screens render without errors
/// 2. Navigation buttons exist and are tappable
/// 3. State management integrations display correctly
/// 4. Key widgets are identifiable by their semantic keys

Widget _wrapWithProviders(Widget child) {
  return ProviderScope(
    child: BlocProvider(
      create: (_) => CounterCubit(),
      child: MaterialApp(
        home: child,
        routes: {
          '/state': (_) => const StateInjectionScreen(),
          '/network': (_) => const Scaffold(body: Text('network')),
          '/storage': (_) => const Scaffold(body: Text('storage')),
          '/chaos': (_) => const ChaosScreen(),
        },
      ),
    ),
  );
}

void main() {
  group('DashboardScreen', () {
    testWidgets('renders title and auth status', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const DashboardScreen()));

      expect(find.text('FlutterPilot Dashboard'), findsOneWidget);
      expect(find.byKey(const Key('auth_status_text')), findsOneWidget);
      expect(find.text('Status: Guest'), findsOneWidget);
    });

    testWidgets('has all navigation buttons', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const DashboardScreen()));

      expect(find.byKey(const Key('nav_state_button')), findsOneWidget);
      expect(find.byKey(const Key('nav_network_button')), findsOneWidget);
      expect(find.byKey(const Key('nav_storage_button')), findsOneWidget);
      expect(find.byKey(const Key('nav_chaos_button')), findsOneWidget);
    });

    testWidgets('navigates to state injection screen', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const DashboardScreen()));

      await tester.tap(find.byKey(const Key('nav_state_button')));
      await tester.pumpAndSettle();

      expect(find.text('State Injection Testing'), findsOneWidget);
    });
  });

  group('StateInjectionScreen', () {
    testWidgets('renders Riverpod and Bloc counters', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const StateInjectionScreen()));

      expect(find.byKey(const Key('riverpod_count_text')), findsOneWidget);
      expect(find.byKey(const Key('bloc_count_text')), findsOneWidget);
    });

    testWidgets('Bloc counter increments on tap', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const StateInjectionScreen()));

      // Value is in its own Text widget (keyPrefix_count_text)
      final blocText = find.byKey(const Key('bloc_count_text'));
      expect(tester.widget<Text>(blocText).data, '0');

      await tester.tap(find.byKey(const Key('bloc_increment_button')));
      await tester.pump();

      expect(tester.widget<Text>(blocText).data, '1');
    });

    testWidgets('Riverpod counter increments on tap', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const StateInjectionScreen()));

      final riverpodText = find.byKey(const Key('riverpod_count_text'));
      expect(tester.widget<Text>(riverpodText).data, '0');

      await tester.tap(find.byKey(const Key('riverpod_increment_button')));
      await tester.pump();

      expect(tester.widget<Text>(riverpodText).data, '1');
    });
  });

  group('ChaosScreen', () {
    testWidgets('renders crash buttons', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const ChaosScreen()));

      expect(find.text('Chaos & Self-Heal'), findsOneWidget);
      expect(find.text('Trigger Sync Error'), findsOneWidget);
      expect(find.text('Trigger Async Error'), findsOneWidget);
    });
  });
}
