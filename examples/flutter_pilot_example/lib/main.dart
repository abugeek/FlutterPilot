import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

// FlutterPilot Imports
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:flutterpilot_riverpod/flutterpilot_riverpod.dart';
import 'package:flutterpilot_dio/flutterpilot_dio.dart';
import 'package:flutterpilot_hive/flutterpilot_hive.dart';

// App Imports
import 'src/screens/dashboard_screen.dart';
import 'src/screens/state_injection_screen.dart';
import 'src/screens/chaos_screen.dart';
import 'src/screens/network_screen.dart';
import 'src/screens/storage_screen.dart';
import 'src/state/bloc_state.dart';

/// Shared Dio instance with the FlutterPilot interceptor attached.
final dio = Dio()..interceptors.add(DioPilotInterceptor());

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize FlutterPilot SDK
  FlutterPilot.initialize();

  // 2. Initialize Hive and register with FlutterPilot
  await Hive.initFlutter();
  final settingsBox = await Hive.openBox('settings');
  HivePilotInspector.registerBox('settings');

  runApp(
    // 3. Wrap with Riverpod and Bloc providers
    ProviderScope(
      observers: [RiverpodPilotObserver()],
      child: BlocProvider(
        create: (_) => CounterCubit(),
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
    return MaterialApp(
      title: 'FlutterPilot Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      // 4. Register Navigation Observer
      navigatorObservers: [NavigationTracker()],
      initialRoute: '/',
      routes: {
        '/': (context) => const DashboardScreen(),
        '/state': (context) => const StateInjectionScreen(),
        '/chaos': (context) => const ChaosScreen(),
        '/network': (context) => NetworkScreen(dio: dio),
        '/storage': (context) => StorageScreen(settingsBox: settingsBox),
      },
    );
  }
}
