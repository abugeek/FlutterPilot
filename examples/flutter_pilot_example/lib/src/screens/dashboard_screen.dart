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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FlutterPilot Dashboard'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status & User Banner
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status: ${isLoggedIn ? "Authenticated" : "Guest"}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      key: const Key('auth_status_text'),
                    ),
                    if (user != null)
                      Text(
                        'User: ${user.name} (${user.email})',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        key: const Key('user_info_text'),
                      ),
                  ],
                ),
                Chip(
                  avatar: Icon(
                    isLoggedIn ? Icons.lock_open : Icons.person_outline,
                    size: 16,
                  ),
                  label: Text(isLoggedIn ? 'Active' : 'Guest'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Mission Control Card
            Card(
              key: const Key('pilot_control_center_card'),
              elevation: 0,
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.flight_takeoff,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'FlutterPilot Mission Control',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Autonomous agent is connected and controlling the emulator session in real-time.',
                      key: const Key('pilot_mission_status_text'),
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      key: const Key('run_health_sweep_button'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '⚡ FlutterPilot Autonomous Health Sweep Executed! All systems operational.',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      icon: const Icon(Icons.verified, size: 18),
                      label: const Text('Execute Autonomous Health Sweep'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Section 1: Core Architecture
            _buildSectionHeader(
              context,
              title: 'State & Data Architecture',
              icon: Icons.hub_outlined,
            ),
            const SizedBox(height: 10),
            _buildModuleGrid(
              context,
              modules: const [
                _ModuleItem(
                  label: 'State Injection',
                  route: '/state',
                  icon: Icons.input,
                  subtitle: 'Bloc, Riverpod, state injection',
                ),
                _ModuleItem(
                  label: 'Network & Logs',
                  route: '/network',
                  icon: Icons.network_check,
                  subtitle: 'HTTP, mock responses, logs',
                ),
                _ModuleItem(
                  label: 'Storage (Hive)',
                  route: '/storage',
                  icon: Icons.storage,
                  subtitle: 'Hive key-value inspector',
                ),
                _ModuleItem(
                  label: 'Connectivity',
                  route: '/connectivity',
                  icon: Icons.wifi,
                  subtitle: 'Network status, offline simulation',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Section 2: UI & User Experience
            _buildSectionHeader(
              context,
              title: 'UI & User Experience',
              icon: Icons.palette_outlined,
            ),
            const SizedBox(height: 10),
            _buildModuleGrid(
              context,
              modules: const [
                _ModuleItem(
                  label: 'UI Automation',
                  route: '/ui_automation',
                  icon: Icons.touch_app,
                  subtitle: 'Tap, type, scroll, forms',
                ),
                _ModuleItem(
                  label: 'Navigation',
                  route: '/navigation',
                  icon: Icons.navigation,
                  subtitle: 'Routes, theme, locale',
                ),
                _ModuleItem(
                  label: 'Accessibility',
                  route: '/accessibility',
                  icon: Icons.accessibility_new,
                  subtitle: 'Semantics, touch-targets',
                ),
                _ModuleItem(
                  label: 'Animation Lab',
                  route: '/animation_lab',
                  icon: Icons.animation,
                  subtitle: 'Physics & spring curves',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Section 3: Reliability & DevTools
            _buildSectionHeader(
              context,
              title: 'Reliability & Inspection',
              icon: Icons.health_and_safety_outlined,
            ),
            const SizedBox(height: 10),
            _buildModuleGrid(
              context,
              modules: const [
                _ModuleItem(
                  label: 'Chaos (Self-Heal)',
                  route: '/chaos',
                  icon: Icons.auto_fix_high,
                  subtitle: 'Error injection & recovery',
                ),
                _ModuleItem(
                  label: 'Debug & Performance',
                  route: '/debug_perf',
                  icon: Icons.speed,
                  subtitle: 'Logs, memory, frame budget',
                ),
                _ModuleItem(
                  label: 'Testing & Screenshots',
                  route: '/testing',
                  icon: Icons.camera_alt,
                  subtitle: 'Screenshots, golden baselines',
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildModuleGrid(
    BuildContext context, {
    required List<_ModuleItem> modules,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: modules.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
      ),
      itemBuilder: (context, index) {
        final item = modules[index];
        return _NavCard(item: item);
      },
    );
  }
}

class _ModuleItem {
  final String label;
  final String route;
  final IconData icon;
  final String subtitle;

  const _ModuleItem({
    required this.label,
    required this.route,
    required this.icon,
    required this.subtitle,
  });
}

class _NavCard extends StatelessWidget {
  final _ModuleItem item;

  const _NavCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyName = 'nav_${item.route.substring(1)}_button';

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key(keyName),
        onTap: () => context.push(item.route),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.icon,
                  size: 18,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.0,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
