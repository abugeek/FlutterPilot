import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// FlutterPilot Imports
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:flutterpilot_riverpod/flutterpilot_riverpod.dart';

// App Imports
import 'src/screens/dashboard_screen.dart';
import 'src/screens/state_injection_screen.dart';
import 'src/screens/chaos_screen.dart';
import 'src/state/bloc_state.dart';

void main() {
  // 1. Initialize FlutterPilot
  FlutterPilot.initialize();

  runApp(
    // 2. Wrap with Riverpod and Bloc providers
    ProviderScope(
      observers: [RiverpodPilotObserver()],
      child: BlocProvider(
        create: (_) => CounterCubit(),
        child: const MainApp(),
      ),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlutterPilot Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      // 3. Register Navigation Observer
      navigatorObservers: [NavigationTracker()],
      initialRoute: '/',
      routes: {
        '/': (context) => const DashboardScreen(),
        '/state': (context) => const StateInjectionScreen(),
        '/chaos': (context) => const ChaosScreen(),
        // Placeholder for other screens
        '/network': (context) => _PlaceholderScreen(title: 'Network Logs'),
        '/storage': (context) =>
            _PlaceholderScreen(title: 'Storage Inspection'),
      },
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(
        child: Text('Coming soon... (Demo the existing features first!)'),
      ),
    );
  }
}
