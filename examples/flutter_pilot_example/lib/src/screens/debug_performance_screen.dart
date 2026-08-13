import 'dart:developer' as developer;
import 'package:flutter/material.dart';

/// Demonstrates debug, logging, and performance DevTools tools:
///
/// | Tool                          | Demonstrated By                   |
/// |-------------------------------|-----------------------------------|
/// | get_debug_logs                | emit-logs button                  |
/// | set_log_filter                | hint code box                     |
/// | clear_debug_logs              | hint code box                     |
/// | get_errors                    | report-error button               |
/// | diagnose_last_error           | hint code box                     |
/// | get_perf_metrics              | perf metrics card                 |
/// | show_performance_overlay      | toggle switch                     |
/// | toggle_repaint_rainbow        | toggle switch                     |
/// | toggle_debug_paint            | toggle switch                     |
/// | toggle_slow_animations        | toggle switch                     |
/// | enable_widget_rebuild_tracking| toggle switch                     |
/// | get_memory_details            | memory card hint                  |
/// | get_gc_stats                  | gc card hint                      |
/// | get_render_tree               | devtools card hint                |
/// | get_layer_tree                | devtools card hint                |
/// | get_vm_info                   | devtools card hint                |
/// | get_allocation_profile        | devtools card hint                |
/// | get_http_profile              | devtools card hint                |
class DebugPerformanceScreen extends StatefulWidget {
  const DebugPerformanceScreen({super.key});

  @override
  State<DebugPerformanceScreen> createState() => _DebugPerformanceScreenState();
}

class _DebugPerformanceScreenState extends State<DebugPerformanceScreen> {
  bool _showPerfOverlay = false;
  bool _repaintRainbow = false;
  bool _debugPaint = false;
  bool _slowAnimations = false;
  bool _rebuildTracking = false;
  int _logCount = 0;

  void _emitLogs() {
    const levels = ['INFO', 'DEBUG', 'WARNING', 'ERROR', 'VERBOSE'];
    for (int i = 0; i < 5; i++) {
      developer.log(
        '[${levels[i % 5]}] Log #${_logCount + i + 1}: ${DateTime.now().toIso8601String()}',
        name: 'FPExample',
        level: 800 + i * 100,
      );
    }
    setState(() => _logCount += 5);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('5 logs emitted. Call get_debug_logs to read them.'),
      ),
    );
  }

  void _triggerError() {
    try {
      throw StateError('Intentional error for diagnose_last_error demo');
    } catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'FPExample',
          context: ErrorDescription('DebugPerformanceScreen'),
        ),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Error captured. Call get_errors or diagnose_last_error.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug & Performance')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _aiHint(
              'Tools on this screen:\n'
              '  get_debug_logs  clear_debug_logs  set_log_filter\n'
              '  get_errors  diagnose_last_error  get_perf_metrics\n'
              '  show_performance_overlay  toggle_repaint_rainbow\n'
              '  toggle_debug_paint  toggle_slow_animations\n'
              '  enable_widget_rebuild_tracking\n'
              '  get_memory_details  get_gc_stats  get_vm_info\n'
              '  get_allocation_profile  get_render_tree',
            ),
            const SizedBox(height: 16),

            // -- Debug Logs --------------------------------------------------
            _sectionHeader(
              'Debug Logs',
              'get_debug_logs · clear_debug_logs · set_log_filter',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FlutterPilot captures the debug console in a ring buffer.\n'
                      'Tap below to emit logs, then use get_debug_logs to read them.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      key: const Key('emit_logs_button'),
                      onPressed: _emitLogs,
                      icon: const Icon(Icons.comment),
                      label: Text('Emit 5 Logs ($_logCount total emitted)'),
                    ),
                    const SizedBox(height: 8),
                    _codeBox(
                      'get_debug_logs(lines: 20)\n'
                      'set_log_filter("ERROR")\n'
                      'clear_debug_logs',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // -- Error Detection ---------------------------------------------
            _sectionHeader(
              'Error Detection',
              'get_errors · diagnose_last_error',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'get_errors returns errors captured by FlutterError.onError.\n'
                      'diagnose_last_error returns an AI-friendly root-cause analysis.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      key: const Key('trigger_reported_error_button'),
                      onPressed: _triggerError,
                      icon: const Icon(Icons.error_outline),
                      label: const Text('Report a Handled Error'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade50,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _codeBox(
                      '// After tapping:\n'
                      'get_errors              // list captured errors\n'
                      'diagnose_last_error     // AI analysis',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // -- Performance Metrics ----------------------------------------
            _sectionHeader(
              'Performance Metrics',
              'get_perf_metrics · show_performance_overlay',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'get_perf_metrics returns current FPS, frame build/raster times.\n'
                      'show_performance_overlay displays the timeline bars on screen.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const Key('perf_overlay_switch'),
                      title: const Text(
                        'Performance Overlay (show_performance_overlay)',
                      ),
                      subtitle: const Text(
                        'Displays rendering bars at the top of the screen',
                      ),
                      value: _showPerfOverlay,
                      onChanged: (v) {
                        setState(() => _showPerfOverlay = v);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'AI: show_performance_overlay(show: $v)',
                            ),
                          ),
                        );
                      },
                    ),
                    _codeBox(
                      'get_perf_metrics                  // read FPS + frame times\n'
                      'show_performance_overlay(show: true)',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // -- DevTools Toggles -------------------------------------------
            _sectionHeader(
              'DevTools Visual Toggles',
              'toggle_repaint_rainbow · toggle_debug_paint · '
                  'toggle_slow_animations · enable_widget_rebuild_tracking',
            ),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('repaint_rainbow_switch'),
                    title: const Text('Repaint Rainbow'),
                    subtitle: const Text(
                      'Colors widgets that repaint — spot unnecessary rebuilds',
                    ),
                    value: _repaintRainbow,
                    onChanged: (v) {
                      setState(() => _repaintRainbow = v);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'AI: toggle_repaint_rainbow(enabled: $v)',
                          ),
                        ),
                      );
                    },
                  ),
                  SwitchListTile(
                    key: const Key('debug_paint_switch'),
                    title: const Text('Debug Paint'),
                    subtitle: const Text(
                      'Shows layout bounds, padding, and hit-test regions',
                    ),
                    value: _debugPaint,
                    onChanged: (v) {
                      setState(() => _debugPaint = v);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('AI: toggle_debug_paint(enabled: $v)'),
                        ),
                      );
                    },
                  ),
                  SwitchListTile(
                    key: const Key('slow_animations_switch'),
                    title: const Text('Slow Animations (5x)'),
                    subtitle: const Text(
                      'Slows animations to verify correctness',
                    ),
                    value: _slowAnimations,
                    onChanged: (v) {
                      setState(() => _slowAnimations = v);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'AI: toggle_slow_animations(enabled: $v)',
                          ),
                        ),
                      );
                    },
                  ),
                  SwitchListTile(
                    key: const Key('rebuild_tracking_switch'),
                    title: const Text('Widget Rebuild Tracking'),
                    subtitle: const Text(
                      'Highlights widgets that rebuilt in the last frame',
                    ),
                    value: _rebuildTracking,
                    onChanged: (v) {
                      setState(() => _rebuildTracking = v);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'AI: enable_widget_rebuild_tracking(enabled: $v)',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // -- Memory & GC ------------------------------------------------
            _sectionHeader(
              'Memory & GC',
              'get_memory_details · get_gc_stats · get_allocation_profile',
            ),
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'These tools query the Dart VM for memory statistics.\n'
                      'Useful for spotting leaks, large allocations, and GC pressure.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _codeBox(
                      'get_memory_details      // heap usage, external, RSS\n'
                      'get_gc_stats            // full/partial GC counts + time\n'
                      'get_allocation_profile  // per-class allocation counts',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // -- Deep DevTools -----------------------------------------------
            _sectionHeader(
              'Deep DevTools Inspection',
              'get_render_tree · get_layer_tree · get_vm_info · get_http_profile',
            ),
            Card(
              color: Colors.indigo.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Advanced tools that mirror Flutter DevTools capabilities:',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _codeBox(
                      'get_render_tree         // RenderObject tree\n'
                      'get_layer_tree          // compositing layer tree\n'
                      'get_vm_info            // Dart VM version + isolates\n'
                      'get_http_profile        // timeline of dart:io requests\n'
                      'clear_http_profile      // reset request timeline',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tip: Combine get_render_tree with get_widget_tree to '
                      'correlate layout problems with specific widgets.',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
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

  Widget _codeBox(String code) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Text(
      code,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
    ),
  );
}
