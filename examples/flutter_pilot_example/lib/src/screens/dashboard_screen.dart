import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/riverpod_state.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(authProvider);
    final user = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('FlutterPilot Dashboard')),
      body: Padding(
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
        onPressed: () => Navigator.pushNamed(context, route),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
