import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../state/bloc_state.dart';

/// Demonstrates all navigation and routing tools:
///
/// | Tool                 | Demonstrated By                         |
/// |----------------------|-----------------------------------------|
/// | navigate_to          | buttons push named routes               |
/// | press_back           | back button in app bar                  |
/// | get_navigation_stack | AI can read stack at any time           |
/// | simulate_deep_link   | deep-link hint with example URL         |
/// | set_theme            | light/dark toggle via ThemeCubit        |
/// | set_locale           | locale dropdown (en/es/fr/de/ar)        |
/// | set_device_rotation  | portrait/landscape toggle               |
/// | wait_for_state       | async navigation demo                   |
class NavigationFeaturesScreen extends StatefulWidget {
  const NavigationFeaturesScreen({super.key});

  @override
  State<NavigationFeaturesScreen> createState() =>
      _NavigationFeaturesScreenState();
}

class _NavigationFeaturesScreenState extends State<NavigationFeaturesScreen> {
  String _currentLocale = 'en_US';
  bool _isPortrait = true;
  bool _pendingNavigation = false;

  final _locales = ['en_US', 'es_ES', 'fr_FR', 'de_DE', 'ar_SA', 'ja_JP'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation Features'),
        actions: [
          BlocBuilder<ThemeCubit, bool>(
            builder: (ctx, isDark) => IconButton(
              key: const Key('theme_toggle_button'),
              icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              tooltip: 'Toggle theme (set_theme)',
              onPressed: () => ctx.read<ThemeCubit>().toggle(),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _aiHint(
              'AI Agent hints:\n'
              '  navigate_to("/state")  navigate_to("/network")\n'
              '  set_theme("dark")  set_locale("es_ES")\n'
              '  simulate_deep_link("flutterpilot://note/123")\n'
              '  get_navigation_stack  press_back',
            ),
            const SizedBox(height: 16),

            _sectionHeader(
              'Navigate To',
              'navigate_to · press_back · get_navigation_stack',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _routeButton(
                          context,
                          '/state',
                          'State Screen',
                          Icons.memory,
                        ),
                        _routeButton(
                          context,
                          '/network',
                          'Network',
                          Icons.network_check,
                        ),
                        _routeButton(
                          context,
                          '/storage',
                          'Storage',
                          Icons.storage,
                        ),
                        _routeButton(
                          context,
                          '/chaos',
                          'Chaos',
                          Icons.bug_report,
                        ),
                        _routeButton(
                          context,
                          '/ui_automation',
                          'UI Automation',
                          Icons.touch_app,
                        ),
                        _routeButton(
                          context,
                          '/accessibility',
                          'Accessibility',
                          Icons.accessibility,
                        ),
                        _routeButton(
                          context,
                          '/debug_perf',
                          'Debug & Perf',
                          Icons.speed,
                        ),
                        _routeButton(
                          context,
                          '/testing',
                          'Testing',
                          Icons.science,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      key: const Key('press_back_button'),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        }
                      },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('press_back'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            _sectionHeader('Theme Switching', 'set_theme'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: BlocBuilder<ThemeCubit, bool>(
                  builder: (ctx, isDark) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current theme: ${isDark ? "dark 🌙" : "light ☀️"}'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton(
                            key: const Key('set_light_theme_button'),
                            onPressed: isDark
                                ? () => ctx.read<ThemeCubit>().toggle()
                                : null,
                            child: const Text('Light'),
                          ),
                          ElevatedButton(
                            key: const Key('set_dark_theme_button'),
                            onPressed: !isDark
                                ? () => ctx.read<ThemeCubit>().toggle()
                                : null,
                            child: const Text('Dark'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'AI: set_theme("dark") or set_theme("light")',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            _sectionHeader('Locale / i18n', 'set_locale'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current locale: $_currentLocale'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const Key('locale_dropdown'),
                      initialValue: _currentLocale,
                      decoration: const InputDecoration(
                        labelText: 'Select locale',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _locales
                          .map(
                            (l) => DropdownMenuItem(value: l, child: Text(l)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _currentLocale = v ?? 'en_US'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'AI: set_locale("es_ES") switches language at runtime',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            _sectionHeader('Device Rotation', 'set_device_rotation'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _isPortrait
                          ? Icons.stay_current_portrait
                          : Icons.stay_current_landscape,
                      size: 48,
                      color: Colors.indigo,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Currently: ${_isPortrait ? "Portrait" : "Landscape"}',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                key: const Key('portrait_button'),
                                onPressed: !_isPortrait
                                    ? () => setState(() => _isPortrait = true)
                                    : null,
                                icon: const Icon(
                                  Icons.stay_current_portrait,
                                  size: 16,
                                ),
                                label: const Text('Portrait'),
                              ),
                              ElevatedButton.icon(
                                key: const Key('landscape_button'),
                                onPressed: _isPortrait
                                    ? () => setState(() => _isPortrait = false)
                                    : null,
                                icon: const Icon(
                                  Icons.stay_current_landscape,
                                  size: 16,
                                ),
                                label: const Text('Landscape'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            _sectionHeader('Deep Links', 'simulate_deep_link'),
            Card(
              color: Colors.purple.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'simulate_deep_link fires a URI into the app routing system.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('Example deep links to try:'),
                    const SizedBox(height: 4),
                    _codeChip('flutterpilot://note/123'),
                    const SizedBox(height: 4),
                    _codeChip('flutterpilot://settings?tab=privacy'),
                    const SizedBox(height: 4),
                    _codeChip('https://app.example.com/login?token=abc'),
                    const SizedBox(height: 8),
                    Text(
                      'AI: simulate_deep_link("flutterpilot://note/42")',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            _sectionHeader('Async wait_for_state', 'wait_for_state'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'wait_for_state pauses AI execution until a condition is true.\n'
                      'Useful after navigate_to to wait for screen load, or after\n'
                      'triggering async operations.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      key: const Key('delayed_nav_button'),
                      onPressed: _pendingNavigation
                          ? null
                          : () async {
                              setState(() => _pendingNavigation = true);
                              await Future.delayed(const Duration(seconds: 2));
                              if (!mounted) return;
                              setState(() => _pendingNavigation = false);
                              // ignore: use_build_context_synchronously
                              context.push('/state');
                            },
                      icon: _pendingNavigation
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.timer),
                      label: Text(
                        _pendingNavigation
                            ? 'Navigating in 2s... (wait_for_state here)'
                            : 'Delayed Navigate (2s)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'AI script:\n'
                      '  1. tap_widget("delayed_nav_button")\n'
                      '  2. wait_for_state(\'route == "/state"\', timeout: 5000)\n'
                      '  3. get_app_summary  // verify navigation succeeded',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _routeButton(
    BuildContext ctx,
    String route,
    String label,
    IconData icon,
  ) {
    return ElevatedButton.icon(
      key: Key('nav_to${route.replaceAll("/", "_")}_button'),
      onPressed: () => ctx.push(route),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _sectionHeader(String title, String tools) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          tools,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    ),
  );

  Widget _aiHint(String text) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.blue.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.blue.shade200),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.smart_toy, color: Colors.blue, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.blue,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _codeChip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.purple.shade100,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: Colors.purple.shade900,
      ),
    ),
  );
}
