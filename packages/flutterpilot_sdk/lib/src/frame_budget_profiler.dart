import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'ring_buffer.dart';

/// Microsecond-precision frame timing and jank profiler for FlutterPilot.
///
/// Records frame metrics (build, raster, total span) over a rolling 120-frame
/// window using Flutter's native [WidgetsBinding.addTimingsCallback].
class FrameBudgetProfiler {
  static const int bufferSize = 120;
  static final RingBuffer<Map<String, dynamic>> _frameTimings = RingBuffer(bufferSize);
  static bool _installed = false;

  static double get _frameBudgetMs {
    final refreshRate = WidgetsBinding.instance.platformDispatcher.implicitView?.display.refreshRate ?? 60.0;
    return 1000.0 / refreshRate.clamp(1.0, 240.0);
  }

  /// Installs the frame timing listener. Safe to call multiple times.
  static void initialize() {
    if (_installed) return;
    _installed = true;

    try {
      WidgetsBinding.instance.addTimingsCallback(_onTimings);
    } catch (_) {}
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final buildMs = t.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = t.rasterDuration.inMicroseconds / 1000.0;
      final totalMs = t.totalSpan.inMicroseconds / 1000.0;
      final isJanky = totalMs > _frameBudgetMs;

      _frameTimings.add({
        'buildMs': buildMs,
        'rasterMs': rasterMs,
        'totalMs': totalMs,
        'isJanky': isJanky,
        'vsyncOverheadMs': t.vsyncOverhead.inMicroseconds / 1000.0,
      });
    }
  }

  /// Calculates aggregate frame budget diagnostics and root cause analysis.
  static Map<String, dynamic> getProfile() {
    final frames = _frameTimings.toList();
    if (frames.isEmpty) {
      return {
        'status': 'no_frames_recorded',
        'sampleCount': 0,
        'fps': 60.0,
        'frameBudgetMs': double.parse(_frameBudgetMs.toStringAsFixed(2)),
        'jankPercentage': 0.0,
      };
    }

    final totals = frames.map((f) => f['totalMs'] as double).toList()..sort();
    final builds = frames.map((f) => f['buildMs'] as double).toList();
    final rasters = frames.map((f) => f['rasterMs'] as double).toList();

    final count = frames.length;
    final jankyCount = frames.where((f) => f['isJanky'] == true).length;
    final avgTotal = totals.reduce((a, b) => a + b) / count;
    final avgBuild = builds.reduce((a, b) => a + b) / count;
    final avgRaster = rasters.reduce((a, b) => a + b) / count;

    final p50 = totals[(count * 0.50).floor().clamp(0, count - 1)];
    final p90 = totals[(count * 0.90).floor().clamp(0, count - 1)];
    final p99 = totals[(count * 0.99).floor().clamp(0, count - 1)];
    final worst = totals.last;

    String? diagnosis;
    if (jankyCount > 0) {
      if (avgBuild > _frameBudgetMs * 0.9) {
        diagnosis = 'UI Thread Bottleneck: Build/Layout phase is taking ${avgBuild.toStringAsFixed(1)}ms on average. '
            'Check for expensive operations inside build() or non-lazy list rendering.';
      } else if (avgRaster > _frameBudgetMs * 0.9) {
        diagnosis = 'GPU Thread Bottleneck: Rasterization phase is taking ${avgRaster.toStringAsFixed(1)}ms on average. '
            'Check for excessive saveLayer calls, uncompressed image decodes, or complex clipping masks.';
      } else {
        diagnosis = 'Occasional frame spikes detected ($jankyCount of $count frames exceeded the ${_frameBudgetMs.toStringAsFixed(2)}ms budget).';
      }
    }

    return {
      'sampleCount': count,
      'frameBudgetMs': double.parse(_frameBudgetMs.toStringAsFixed(2)),
      'jankCount': jankyCount,
      'jankPercentage': (jankyCount / count) * 100.0,
      'avgFrameDurationMs': double.parse(avgTotal.toStringAsFixed(2)),
      'avgBuildDurationMs': double.parse(avgBuild.toStringAsFixed(2)),
      'avgRasterDurationMs': double.parse(avgRaster.toStringAsFixed(2)),
      'p50FrameMs': double.parse(p50.toStringAsFixed(2)),
      'p90FrameMs': double.parse(p90.toStringAsFixed(2)),
      'p99FrameMs': double.parse(p99.toStringAsFixed(2)),
      'worstFrameMs': double.parse(worst.toStringAsFixed(2)),
      'effectiveFps': double.parse((1000.0 / (avgTotal > 0 ? avgTotal : 16.6)).clamp(1.0, 120.0).toStringAsFixed(1)),
      if (diagnosis != null) 'diagnosis': diagnosis,
    };
  }

  /// Clears recorded frame samples.
  static void clear() {
    _frameTimings.clear();
  }
}
