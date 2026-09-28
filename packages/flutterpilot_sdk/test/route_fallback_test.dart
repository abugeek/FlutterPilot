import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:go_router/go_router.dart';

/// A MaterialApp.router app with no NavigationTracker and no router plugin:
/// the route comes from the pages in the widget tree.
GoRouter _router() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => Scaffold(
        body: Column(
          children: [
            TextButton(
              onPressed: () => context.go('/details'),
              child: const Text('Go'),
            ),
            TextButton(
              onPressed: () => context.push('/details'),
              child: const Text('Push'),
            ),
            TextButton(
              onPressed: () => context.go('/tabs/b'),
              child: const Text('Tabs'),
            ),
          ],
        ),
      ),
    ),
    GoRoute(
      path: '/details',
      builder: (context, _) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(title: Text('Hi')),
          ),
          child: const Text('Dialog'),
        ),
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => Scaffold(body: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/tabs/a', builder: (_, _) => const Text('A')),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/tabs/b', builder: (_, _) => const Text('B')),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  setUp(NavigationTracker.reset);

  testWidgets('no router app: the route is unknown, not invented', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    expect(NavigationTracker.currentRoute, NavigationTracker.unknown);
  });

  testWidgets('go, push and a dialog are named from the on-screen page', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    expect(NavigationTracker.currentRoute, '/');

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(NavigationTracker.currentRoute, '/details');
    expect(NavigationTracker.stack, ['/details']);

    await tester.tap(find.text('Dialog'));
    await tester.pumpAndSettle();
    expect(NavigationTracker.currentRoute, '(dialog)');
  });

  testWidgets('a pushed page sits on top of the one it covers', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    expect(NavigationTracker.stack, ['/', '/details']);
  });

  testWidgets('a hidden shell branch is not the current route', (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go('/tabs/a');
    await tester.pumpAndSettle();
    expect(NavigationTracker.currentRoute, '/tabs/a');
    // Branch A stays built (IndexedStack) but hidden behind B.
    router.go('/tabs/b');
    await tester.pumpAndSettle();
    expect(NavigationTracker.currentRoute, '/tabs/b');
    router.go('/tabs/a');
    await tester.pumpAndSettle();
    expect(NavigationTracker.currentRoute, '/tabs/a');
  });

  testWidgets('post-action state reports the navigation', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    final before = NavigationTracker.currentRoute;
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    final post = await FlutterPilot.getPostActionState(previousRoute: before);
    expect(post['route'], '/details');
    expect(post['routeChanged'], isTrue);
    expect(post['previousRoute'], '/');
  });

  testWidgets('an observer, when there is one, still wins', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [NavigationTracker()],
        initialRoute: '/start',
        routes: {'/start': (_) => const Text('Start')},
      ),
    );
    expect(NavigationTracker.currentRoute, '/start');
  });
}
