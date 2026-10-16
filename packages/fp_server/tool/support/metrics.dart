// Percentile summaries shared by the development benchmarks (task 09's startup
// benchmark and task 10's analyzer-fallback measurement).
//
// p95 is nearest rank, which is descriptive of a small sample, not a stable
// SLA. An empty sample is reported as `{n: 0}` rather than a fabricated value,
// so a case that produced no usable trial is visible, never silently zero.
//
// Development-tool support, not shipped code.
library;

/// Median, p95 (nearest rank), min, max and sample count for [values], in
/// milliseconds. Returns `{n: 0}` when [values] is empty.
Map<String, dynamic> summarizeMs(List<int> values) {
  if (values.isEmpty) return {'n': 0};
  final sorted = [...values]..sort();
  final n = sorted.length;
  final double median = n.isOdd
      ? sorted[n ~/ 2].toDouble()
      : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  final p95 = sorted[(0.95 * n).ceil().clamp(1, n) - 1];
  return {
    'n': n,
    'median': median,
    'p95': p95,
    'min': sorted.first,
    'max': sorted.last,
  };
}
