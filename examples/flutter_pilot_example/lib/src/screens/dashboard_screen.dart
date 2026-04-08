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
                ),
                _NavButton(
                  label: 'Network & Logs',
                  route: '/network',
                  icon: Icons.network_check,
                ),
                _NavButton(
                  label: 'Storage (Drift/Hive)',
                  route: '/storage',
                  icon: Icons.storage,
                ),
                _NavButton(
                  label: 'Chaos (Self-Heal)',
                  route: '/chaos',
                  icon: Icons.bug_report,
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
  const _NavButton({
    required this.label,
    required this.route,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      key: Key('nav_${route.substring(1)}_button'),
      onPressed: () => Navigator.pushNamed(context, route),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
