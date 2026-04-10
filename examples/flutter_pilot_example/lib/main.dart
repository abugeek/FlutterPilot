import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

// FlutterPilot Imports
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:flutterpilot_riverpod/flutterpilot_riverpod.dart';
import 'package:flutterpilot_bloc/flutterpilot_bloc.dart';
import 'package:flutterpilot_dio/flutterpilot_dio.dart';
import 'package:flutterpilot_hive/flutterpilot_hive.dart';
import 'package:flutterpilot_shared_preferences/flutterpilot_shared_preferences.dart';
import 'package:flutterpilot_gorouter/flutterpilot_gorouter.dart';
import 'package:flutterpilot_connectivity/flutterpilot_connectivity.dart';

// App Imports
import 'src/screens/dashboard_screen.dart';
import 'src/screens/state_injection_screen.dart';
import 'src/screens/chaos_screen.dart';
import 'src/screens/network_screen.dart';
import 'src/screens/storage_screen.dart';
import 'src/screens/ui_automation_screen.dart';
import 'src/screens/navigation_features_screen.dart';
import 'src/screens/debug_performance_screen.dart';
import 'src/screens/accessibility_screen.dart';
import 'src/screens/testing_screen.dart';
import 'src/screens/connectivity_screen.dart';
import 'src/state/bloc_state.dart';

late final Dio dio;

/// Initializes all plugins and returns the root widget.
/// Exposed for integration tests so they can await full initialization.
Future<Widget> initializeApp() async {
  // 1. Initialize FlutterPilot SDK
  FlutterPilot.initialize();

  // 2. Set up Bloc observer for FlutterPilot
  Bloc.observer = BlocPilotObserver();

  // 3. Initialize Dio with FlutterPilot interceptor
  dio = Dio()..interceptors.add(DioPilotInterceptor());

  // 4. Initialize Hive and register with FlutterPilot
  await Hive.initFlutter();
  final settingsBox = await Hive.openBox('settings');
  HivePilotInspector.registerBox('settings');

  // 5. Initialize SharedPreferences and register with FlutterPilot
  final prefs = await SharedPreferences.getInstance();
  SharedPrefsPilotInspector.register(prefs);

  // 6. Initialize Connectivity plugin
  ConnectivityPilotInspector.register();

  return ProviderScope(
    observers: [RiverpodPilotObserver()],
    child: MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => CounterCubit()),
        BlocProvider(create: (_) => ThemeCubit()),
      ],
      child: MainApp(settingsBox: settingsBox),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await initializeApp());
}

class MainApp extends StatefulWidget {
  final Box settingsBox;
  const MainApp({super.key, required this.settingsBox});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/',
      observers: [NavigationTracker()],
      routes: [
        GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/state', builder: (_, __) => const StateInjectionScreen()),
        GoRoute(path: '/chaos', builder: (_, __) => const ChaosScreen()),
        GoRoute(path: '/network', builder: (context, _) => NetworkScreen(dio: dio)),
        GoRoute(
          path: '/storage',
          builder: (context, _) => StorageScreen(settingsBox: widget.settingsBox),
        ),
        GoRoute(path: '/ui_automation', builder: (_, __) => const UiAutomationScreen()),
        GoRoute(path: '/navigation', builder: (_, __) => const NavigationFeaturesScreen()),
        GoRoute(path: '/debug_perf', builder: (_, __) => const DebugPerformanceScreen()),
        GoRoute(path: '/accessibility', builder: (_, __) => const AccessibilityScreen()),
        GoRoute(path: '/testing', builder: (_, __) => const TestingScreen()),
        GoRoute(path: '/connectivity', builder: (_, __) => const ConnectivityScreen()),
      ],
    );
    // Register GoRouter with FlutterPilot for AI agent navigation visibility
    GoRouterPilotInspector.register(_router);
  }

  @override
  void dispose() {
    GoRouterPilotInspector.reset();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, bool>(
      builder: (context, isDark) {
        return MaterialApp.router(
          title: 'FlutterPilot Example',
          routerConfig: _router,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        );
      },
    );
  }
}
