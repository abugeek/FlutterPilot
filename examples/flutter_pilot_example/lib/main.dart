import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterpilot_dio/flutterpilot_dio.dart';
import 'package:flutterpilot_gorouter/flutterpilot_gorouter.dart';
import 'package:flutterpilot_riverpod/flutterpilot_riverpod.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:flutterpilot_shared_preferences/flutterpilot_shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens.dart';
import 'state.dart';
import 'todo_api.dart';

Future<void> main() async {
  FlutterPilot.initialize();
  WidgetsFlutterBinding.ensureInitialized();

  final dio = Dio(BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'))
    ..interceptors.add(DioPilotInterceptor());
  final prefs = await SharedPreferences.getInstance();
  final router = buildRouter();
  SharedPrefsPilotInspector.register(prefs);
  GoRouterPilotInspector.register(router);

  runApp(
    ProviderScope(
      observers: [RiverpodPilotObserver()],
      // Riverpod 3 retries a failed provider forever by default: show the
      // error (and its Retry button) instead.
      retry: (_, _) => null,
      overrides: [
        apiProvider.overrideWithValue(TodoApi(dio)),
        prefsProvider.overrideWithValue(prefs),
      ],
      child: App(router: router),
    ),
  );
}

GoRouter buildRouter() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const TodoListScreen()),
    GoRoute(path: '/add', builder: (_, _) => const AddTodoScreen()),
    GoRoute(
      path: '/todo/:id',
      builder: (_, state) =>
          TodoScreen(id: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);

class App extends ConsumerWidget {
  const App({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'FlutterPilot example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      themeMode: ref.watch(darkModeProvider) ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
    );
  }
}
