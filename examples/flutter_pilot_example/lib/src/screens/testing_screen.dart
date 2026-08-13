import 'package:flutter/material.dart';

/// MCP tools: capture_screenshot, save_screenshot_baseline, compare_screenshot,
/// start_recording, stop_and_generate_test, get_latest_crash_report,
/// list_custom_tools, call_custom_tool, pump_frames, hot_reload.
class TestingScreen extends StatefulWidget {
  const TestingScreen({super.key});
  @override
  State<TestingScreen> createState() => _TestingScreenState();
}

class _TestingScreenState extends State<TestingScreen> {
  bool _isRecording = false;
  int _counter = 0;
  final List<String> _log = [];

  void _addLog(String msg) => setState(() => _log.insert(0, msg));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Testing & Screenshots')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Screenshot Tools', [
            _toolCard(
              icon: Icons.camera_alt,
              title: 'capture_screenshot',
              desc: 'Capture current screen as PNG',
              widgetKey: const Key('capture_screenshot_button'),
              color: Colors.blue,
              onTap: () => _addLog('capture_screenshot -> base64 PNG'),
            ),
            _toolCard(
              icon: Icons.save,
              title: 'save_screenshot_baseline',
              desc: 'Save screenshot as named baseline',
              widgetKey: const Key('save_baseline_button'),
              color: Colors.green,
              onTap: () =>
                  _addLog('save_screenshot_baseline(name: testing_screen)'),
            ),
            _toolCard(
              icon: Icons.compare,
              title: 'compare_screenshot',
              desc: 'Diff current screen vs saved baseline',
              widgetKey: const Key('compare_screenshot_button'),
              color: Colors.purple,
              onTap: () =>
                  _addLog('compare_screenshot(name: testing_screen) -> diff%'),
            ),
          ]),
          const SizedBox(height: 16),
          _section('Recording & Test Generation', [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isRecording
                              ? Icons.stop_circle
                              : Icons.fiber_manual_record,
                          color: _isRecording ? Colors.red : Colors.grey,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isRecording ? 'Recording...' : 'Not Recording',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          key: const Key('start_recording_button'),
                          icon: const Icon(
                            Icons.fiber_manual_record,
                            color: Colors.red,
                          ),
                          label: const Text('start_recording'),
                          onPressed: _isRecording
                              ? null
                              : () {
                                  setState(() => _isRecording = true);
                                  _addLog('start_recording');
                                },
                        ),
                        ElevatedButton.icon(
                          key: const Key('stop_recording_button'),
                          icon: const Icon(Icons.stop),
                          label: const Text('stop_and_generate_test'),
                          onPressed: !_isRecording
                              ? null
                              : () {
                                  setState(() => _isRecording = false);
                                  _addLog(
                                    'stop_and_generate_test -> integration test code',
                                  );
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Record user interactions, then generate Flutter integration tests automatically',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _section('pump_frames Demo', [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Counter: $_counter',
                      key: const Key('pump_counter_label'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ElevatedButton(
                          key: const Key('increment_counter_button'),
                          onPressed: () => setState(() => _counter++),
                          child: const Text('Increment'),
                        ),
                        ElevatedButton(
                          key: const Key('pump_frames_button'),
                          onPressed: () => _addLog('pump_frames(count: 10)'),
                          child: const Text('pump_frames'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'pump_frames advances the Flutter rendering pipeline N frames',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _section('Crash & Custom Tools', [
            _toolCard(
              icon: Icons.bug_report,
              title: 'get_latest_crash_report',
              desc: 'Retrieve the most recent Flutter crash report',
              widgetKey: const Key('get_crash_report_button'),
              color: Colors.red,
              onTap: () => _addLog('get_latest_crash_report -> stack trace'),
            ),
            _toolCard(
              icon: Icons.extension,
              title: 'list_custom_tools',
              desc: 'List all registered custom MCP tool extensions',
              widgetKey: const Key('list_custom_tools_button'),
              color: Colors.teal,
              onTap: () =>
                  _addLog('list_custom_tools -> [my_custom_tool, ...]'),
            ),
            _toolCard(
              icon: Icons.build,
              title: 'call_custom_tool',
              desc: 'Invoke a named custom tool with arguments',
              widgetKey: const Key('call_custom_tool_button'),
              color: Colors.orange,
              onTap: () => _addLog('call_custom_tool(name: my_tool, args: {})'),
            ),
            _toolCard(
              icon: Icons.refresh,
              title: 'hot_reload',
              desc: 'Trigger a Flutter hot reload',
              widgetKey: const Key('hot_reload_button'),
              color: Colors.indigo,
              onTap: () => _addLog('hot_reload -> reloads app code'),
            ),
          ]),
          const SizedBox(height: 16),
          if (_log.isNotEmpty) ...[
            Text('Action Log', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...(_log
                .take(10)
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '> $e',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _toolCard({
    required IconData icon,
    required String title,
    required String desc,
    required Key widgetKey,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        key: widgetKey,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
        onTap: onTap,
      ),
    );
  }
}
