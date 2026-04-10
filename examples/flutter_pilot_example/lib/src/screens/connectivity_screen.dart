import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutterpilot_connectivity/flutterpilot_connectivity.dart';

/// Demonstrates all Connectivity plugin tools:
///
/// | Tool                           | Demonstrated By                         |
/// |--------------------------------|-----------------------------------------|
/// | get_connectivity_status        | live status display                     |
/// | get_connectivity_history       | scrollable event log                    |
/// | simulate_offline               | toggle offline simulation               |
/// | clear_connectivity_history     | clear button                            |
class ConnectivityScreen extends StatefulWidget {
  const ConnectivityScreen({super.key});

  @override
  State<ConnectivityScreen> createState() => _ConnectivityScreenState();
}

class _ConnectivityScreenState extends State<ConnectivityScreen> {
  List<ConnectivityResult> _currentStatus = [ConnectivityResult.none];
  final List<_ConnEvent> _log = [];
  bool _simulatedOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      setState(() {
        _currentStatus = results;
        _log.insert(
          0,
          _ConnEvent(
            time: DateTime.now(),
            status: results.map((r) => r.name).join(', '),
          ),
        );
        if (_log.length > 50) _log.removeLast();
      });
    });
    // Seed initial status
    Connectivity().checkConnectivity().then((results) {
      if (mounted) setState(() => _currentStatus = results);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Color _statusColor(List<ConnectivityResult> results) {
    if (_simulatedOffline) return Colors.red;
    if (results.contains(ConnectivityResult.wifi)) return Colors.green;
    if (results.contains(ConnectivityResult.mobile)) return Colors.blue;
    if (results.contains(ConnectivityResult.ethernet)) return Colors.teal;
    return Colors.orange;
  }

  String _statusLabel(List<ConnectivityResult> results) {
    if (_simulatedOffline) return 'Simulated Offline 🔴';
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return 'No Connection';
    }
    return results.map((r) => r.name.toUpperCase()).join(' + ');
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(_currentStatus);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connectivity'),
        actions: [
          IconButton(
            key: const Key('clear_history_button'),
            icon: const Icon(Icons.clear_all),
            tooltip: 'clear_connectivity_history',
            onPressed: () => setState(() => _log.clear()),
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
              '  get_connectivity_status       → live network type\n'
              '  simulate_offline(true)        → simulates no internet\n'
              '  get_connectivity_history      → event log\n'
              '  clear_connectivity_history    → resets log',
            ),
            const SizedBox(height: 16),

            // ── Current Status ───────────────────────────────────────────────
            _sectionHeader(
              'Current Network Status',
              'get_connectivity_status',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.wifi, color: color, size: 40),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _statusLabel(_currentStatus),
                            key: const Key('connectivity_status_label'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          Text(
                            'Raw: ${_currentStatus.map((r) => r.name).join(', ')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Simulate Offline ─────────────────────────────────────────────
            _sectionHeader('Simulate Offline', 'simulate_offline'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FlutterPilot can toggle a simulated-offline flag that '
                      'your app code can check via '
                      'ConnectivityPilotInspector.isSimulatedOffline. '
                      'AI agents use this to test offline error handling without '
                      'actually losing the network.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Switch(
                          key: const Key('simulate_offline_switch'),
                          value: _simulatedOffline,
                          onChanged: (v) {
                            setState(() => _simulatedOffline = v);
                            ConnectivityPilotInspector.setSimulatedOffline(v);
                            _log.insert(
                              0,
                              _ConnEvent(
                                time: DateTime.now(),
                                status: v
                                    ? 'SIMULATED OFFLINE (injected)'
                                    : 'Simulation cleared',
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _simulatedOffline
                              ? 'Offline simulation ACTIVE'
                              : 'Simulation off',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _simulatedOffline ? Colors.red : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '// In your app code:\n'
                        'if (ConnectivityPilotInspector.isSimulatedOffline) {\n'
                        '  showOfflineBanner();\n'
                        '}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── AI Test Scripts ───────────────────────────────────────────────
            _sectionHeader('AI Test Scripts', 'get_connectivity_status'),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Example AI scripts that use connectivity tools:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _scriptBlock(
                      'Test offline graceful degradation',
                      '1. simulate_offline(true)\n'
                          '2. tap_widget("fetch_posts_button")\n'
                          '3. wait_for_state(\'error_shown == true\', 3000)\n'
                          '4. get_app_summary  // verify error UI shown\n'
                          '5. simulate_offline(false)\n'
                          '6. tap_widget("retry_button")',
                    ),
                    const SizedBox(height: 8),
                    _scriptBlock(
                      'Monitor connectivity during test',
                      '1. get_connectivity_status\n'
                          '   → { type: "wifi", strength: "strong" }\n'
                          '2. // ... run tests ...\n'
                          '3. get_connectivity_history\n'
                          '   → [ { time, event: "wifi→none" }, ... ]',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Event History ─────────────────────────────────────────────────
            _sectionHeader(
              'Connectivity Event History',
              'get_connectivity_history',
            ),
            Card(
              child: _log.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No events yet. Changes in network state will appear here.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      key: const Key('connectivity_history_list'),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _log.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final ev = _log[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            ev.status.contains('SIMULATED')
                                ? Icons.science
                                : Icons.wifi,
                            size: 18,
                            color: ev.status.contains('none')
                                ? Colors.orange
                                : Colors.green,
                          ),
                          title: Text(
                            ev.status,
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: Text(
                            '${ev.time.hour.toString().padLeft(2, '0')}:'
                            '${ev.time.minute.toString().padLeft(2, '0')}:'
                            '${ev.time.second.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
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

  Widget _scriptBlock(String label, String script) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Text(
              script,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      );
}

class _ConnEvent {
  final DateTime time;
  final String status;
  const _ConnEvent({required this.time, required this.status});
}
