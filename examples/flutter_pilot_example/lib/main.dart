import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// FlutterPilot Imports
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:flutterpilot_riverpod/flutterpilot_riverpod.dart';
import 'package:flutterpilot_bloc/flutterpilot_bloc.dart';
import 'package:flutterpilot_dio/flutterpilot_dio.dart';
import 'package:flutterpilot_hive/flutterpilot_hive.dart';
import 'package:flutterpilot_shared_preferences/flutterpilot_shared_preferences.dart';

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
import 'src/state/bloc_state.dart';

late final Dio dio;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(
    // 6. Wrap with Riverpod + Bloc providers (ThemeCubit added for navigation demo)
    ProviderScope(
      observers: [RiverpodPilotObserver()],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => CounterCubit()),
          BlocProvider(create: (_) => ThemeCubit()),
        ],
        child: MainApp(settingsBox: settingsBox),
      ),
    ),
  );
}

class MainApp extends StatelessWidget {
  final Box settingsBox;
  const MainApp({super.key, required this.settingsBox});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, bool>(
      builder: (context, isDark) {
        return MaterialApp(
          title: 'FlutterPilot Example',
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
          navigatorObservers: [NavigationTracker()],
          initialRoute: '/',
          routes: {
            '/': (context) => const DashboardScreen(),
            '/state': (context) => const StateInjectionScreen(),
            '/chaos': (context) => const ChaosScreen(),
            '/network': (context) => NetworkScreen(dio: dio),
            '/storage': (context) => StorageScreen(settingsBox: settingsBox),
            '/ui_automation': (context) => const UiAutomationScreen(),
            '/navigation': (context) => const NavigationFeaturesScreen(),
            '/debug_perf': (context) => const DebugPerformanceScreen(),
            '/accessibility': (context) => const AccessibilityScreen(),
            '/testing': (context) => const TestingScreen(),
          },
        );
      },
    );
  }
}
