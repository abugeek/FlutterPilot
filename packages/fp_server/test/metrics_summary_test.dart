// Tests for the shared percentile summary (tool/support/metrics.dart) used by
// both the task-09 startup benchmark and the task-10 fallback measurement.
library;

import 'package:test/test.dart';

import '../tool/support/metrics.dart';

void main() {
  test('an empty sample is n=0, never a fabricated median', () {
    expect(summarizeMs(const []), {'n': 0});
  });

  test('an odd sample uses the middle value as the median', () {
    final s = summarizeMs([1100, 1300, 1200, 1500, 1400]);
    expect(s['n'], 5);
    expect(s['median'], 1300);
    expect(s['min'], 1100);
    expect(s['max'], 1500);
    // Nearest-rank p95 of 5 samples is the maximum.
    expect(s['p95'], 1500);
  });

  test('an even sample averages the two middle values', () {
    final s = summarizeMs([1, 2, 3, 4]);
    expect(s['median'], 2.5);
    // 0.95 * 4 = 3.8 -> ceil 4 -> index 3.
    expect(s['p95'], 4);
  });

  test('a single sample has median and p95 equal to it', () {
    final s = summarizeMs([42]);
    expect(s['n'], 1);
    expect(s['median'], 42);
    expect(s['p95'], 42);
  });
}
