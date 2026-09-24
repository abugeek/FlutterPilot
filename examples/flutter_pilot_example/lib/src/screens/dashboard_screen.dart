import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../state/riverpod_state.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(authProvider);
    final user = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('FlutterPilot Dashboard')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status: ${isLoggedIn ? "Authenticated" : "Guest"}',
              style: Theme.of(context).textTheme.headlineSmall,
              key: const Key('auth_status_text'),
            ),
            if (user != null) ...[
              const SizedBox(height: 10),
              Text(
                'User: ${user.name} (${user.email})',
                key: const Key('user_info_text'),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Welcome to the FlutterPilot reference app! This app is designed to be fully introspectable by AI agents.',
            ),
            const SizedBox(height: 20),
            Card(
              key: const Key('pilot_control_center_card'),
              elevation: 2,
              color: Colors.indigo.shade50,
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.flight_takeoff, color: Colors.indigo),
                        const SizedBox(width: 8),
                        Text(
                          'FlutterPilot Mission Control',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Autonomous agent is connected and controlling the emulator session in real-time.',
                      key: Key('pilot_mission_status_text'),
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('run_health_sweep_button'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⚡ FlutterPilot Autonomous Health Sweep Executed! All systems operational.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      icon: const Icon(Icons.verified),
                      label: const Text('Execute Autonomous Health Sweep'),
                    ),
                  ],
                ),
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _NavButton(
                  label: 'State Injection',
                  route: '/state',
                  icon: Icons.input,
                  subtitle: 'Bloc, Riverpod, state injection',
                ),
                _NavButton(
                  label: 'Network & Logs',
                  route: '/network',
                  icon: Icons.network_check,
                  subtitle: 'HTTP, mock responses, logs',
                ),
                _NavButton(
                  label: 'Storage (Hive)',
                  route: '/storage',
                  icon: Icons.storage,
                  subtitle: 'Hive key-value inspector',
                ),
                _NavButton(
                  label: 'Chaos (Self-Heal)',
                  route: '/chaos',
                  icon: Icons.auto_fix_high,
                  subtitle: 'Error injection & recovery',
                ),
                _NavButton(
                  label: 'UI Automation',
                  route: '/ui_automation',
                  icon: Icons.touch_app,
                  subtitle: 'Tap, type, scroll, sliders, forms',
                ),
                _NavButton(
                  label: 'Navigation',
                  route: '/navigation',
                  icon: Icons.navigation,
                  subtitle: 'Routes, theme, locale, deep links',
                ),
                _NavButton(
                  label: 'Debug & Performance',
                  route: '/debug_perf',
                  icon: Icons.speed,
                  subtitle: 'Logs, overlays, memory, render tree',
                ),
                _NavButton(
                  label: 'Accessibility',
                  route: '/accessibility',
                  icon: Icons.accessibility_new,
                  subtitle: 'Semantics, text scale, widget states',
                ),
                _NavButton(
                  label: 'Testing & Screenshots',
                  route: '/testing',
                  icon: Icons.camera_alt,
                  subtitle: 'Screenshots, recording, pump_frames',
                ),
                _NavButton(
                  label: 'Connectivity',
                  route: '/connectivity',
                  icon: Icons.wifi,
                  subtitle: 'Network status, offline simulation',
                ),
                _NavButton(
                  label: 'Animation Lab',
                  route: '/animation_lab',
                  icon: Icons.animation,
                  subtitle: 'High-frequency physics animation',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final String label;
  final String route;
  final IconData icon;
  final String subtitle;
  const _NavButton({
    required this.label,
    required this.route,
    required this.icon,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: ElevatedButton(
        key: Key('nav_${route.substring(1)}_button'),
        onPressed: () => context.push(route),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
