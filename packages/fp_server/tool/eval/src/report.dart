// Summaries and comparisons (task 01 §6): per-task medians, a total, and a
// comparison that refuses to compare a changed model, device or app commit.
import 'dart:convert';

import 'agent.dart';

class TaskSummary {
  TaskSummary({
    required this.pass,
    required this.runs,
    required this.callsMedian,
    required this.errorCallsMedian,
    required this.inputTokensMedian,
    required this.outputTokensMedian,
    required this.cacheReadTokensMedian,
    required this.secondsMedian,
    required this.toolsUsed,
  });

  final int pass;
  final int runs;
  final num callsMedian;
  final num errorCallsMedian;
  final num inputTokensMedian;
  final num outputTokensMedian;
  final num cacheReadTokensMedian;
  final num secondsMedian;
  final Map<String, int> toolsUsed;

  Map<String, Object?> toJson() => {
    'pass': pass,
    'runs': runs,
    'calls_median': callsMedian,
    'error_calls_median': errorCallsMedian,
    'input_tokens_median': inputTokensMedian,
    'output_tokens_median': outputTokensMedian,
    'cache_read_tokens_median': cacheReadTokensMedian,
    'seconds_median': secondsMedian,
    'tools_used': toolsUsed,
  };

  static TaskSummary fromJson(Map<String, dynamic> json) => TaskSummary(
    pass: json['pass'] as int,
    runs: json['runs'] as int,
    callsMedian: json['calls_median'] as num,
    errorCallsMedian: json['error_calls_median'] as num,
    inputTokensMedian: json['input_tokens_median'] as num,
    outputTokensMedian: json['output_tokens_median'] as num,
    cacheReadTokensMedian: json['cache_read_tokens_median'] as num,
    secondsMedian: json['seconds_median'] as num,
    toolsUsed: (json['tools_used'] as Map).cast<String, int>(),
  );
}

class AppInfo {
  AppInfo({
    required this.commit,
    required this.toolsListed,
    required this.toolListBytes,
  });

  final String commit;
  final int toolsListed;
  final int toolListBytes;

  Map<String, Object?> toJson() => {
    'commit': commit,
    'tools_listed': toolsListed,
    'tool_list_bytes': toolListBytes,
  };

  static AppInfo fromJson(Map<String, dynamic> json) => AppInfo(
    commit: '${json['commit']}',
    toolsListed: json['tools_listed'] as int,
    toolListBytes: json['tool_list_bytes'] as int,
  );
}

class Totals {
  Totals({
    required this.pass,
    required this.runs,
    required this.passRate,
    required this.callsMedianSum,
    required this.inputTokensMedianSum,
    required this.costUsd,
  });

  final int pass;
  final int runs;
  final double passRate;
  final num callsMedianSum;
  final num inputTokensMedianSum;
  final double costUsd;

  Map<String, Object?> toJson() => {
    'pass': pass,
    'runs': runs,
    'pass_rate': passRate,
    'calls_median_sum': callsMedianSum,
    'input_tokens_median_sum': inputTokensMedianSum,
    'cost_usd': costUsd,
  };

  static Totals fromJson(Map<String, dynamic> json) => Totals(
    pass: json['pass'] as int,
    runs: json['runs'] as int,
    passRate: (json['pass_rate'] as num).toDouble(),
    callsMedianSum: json['calls_median_sum'] as num,
    inputTokensMedianSum: json['input_tokens_median_sum'] as num,
    costUsd: (json['cost_usd'] as num).toDouble(),
  );
}

class RunReport {
  RunReport({
    required this.model,
    required this.device,
    required this.serverCommit,
    required this.apps,
    required this.tasks,
    required this.totals,
  });

  final String model;
  final String device;
  final String serverCommit;
  final Map<String, AppInfo> apps;
  final Map<String, TaskSummary> tasks;
  final Totals totals;

  Map<String, Object?> toJson() => {
    'model': model,
    'device': device,
    'server_commit': serverCommit,
    'apps': {for (final e in apps.entries) e.key: e.value.toJson()},
    'tasks': {for (final e in tasks.entries) e.key: e.value.toJson()},
    'totals': totals.toJson(),
  };

  static RunReport fromJson(Map<String, dynamic> json) => RunReport(
    model: '${json['model']}',
    device: '${json['device']}',
    serverCommit: '${json['server_commit']}',
    apps: {
      for (final e in (json['apps'] as Map).entries)
        '${e.key}': AppInfo.fromJson((e.value as Map).cast<String, dynamic>()),
    },
    tasks: {
      for (final e in (json['tasks'] as Map).entries)
        '${e.key}': TaskSummary.fromJson(
          (e.value as Map).cast<String, dynamic>(),
        ),
    },
    totals: Totals.fromJson((json['totals'] as Map).cast<String, dynamic>()),
  );
}

/// Aggregates one suite's runs into [RunReport] (medians per task, a total).
RunReport summarize({
  required String model,
  required String device,
  required String serverCommit,
  required Map<String, AppInfo> apps,
  required List<TaskRun> results,
}) {
  final byTask = <String, List<TaskRun>>{};
  for (final result in results) {
    byTask.putIfAbsent(result.task.id, () => []).add(result);
  }

  final tasks = <String, TaskSummary>{};
  var pass = 0;
  var runs = 0;
  for (final entry in byTask.entries) {
    final list = entry.value;
    final toolsUsed = <String, int>{};
    for (final result in list) {
      for (final call in result.run.calls) {
        toolsUsed[call.name] = (toolsUsed[call.name] ?? 0) + 1;
      }
    }
    tasks[entry.key] = TaskSummary(
      pass: list.where((r) => r.passed).length,
      runs: list.length,
      callsMedian: _median([for (final r in list) r.run.calls.length]),
      errorCallsMedian: _median([for (final r in list) r.run.errorCalls]),
      inputTokensMedian: _median([for (final r in list) r.run.inputTokens]),
      outputTokensMedian: _median([for (final r in list) r.run.outputTokens]),
      cacheReadTokensMedian: _median([
        for (final r in list) r.run.cacheReadTokens,
      ]),
      secondsMedian: _median([for (final r in list) r.run.seconds]),
      toolsUsed: Map.fromEntries(
        toolsUsed.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      ),
    );
    pass += list.where((r) => r.passed).length;
    runs += list.length;
  }

  return RunReport(
    model: model,
    device: device,
    serverCommit: serverCommit,
    apps: apps,
    tasks: Map.fromEntries(
      tasks.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
    totals: Totals(
      pass: pass,
      runs: runs,
      passRate: runs == 0 ? 0 : pass / runs,
      callsMedianSum: tasks.values.fold(0, (a, t) => a + t.callsMedian),
      inputTokensMedianSum: tasks.values.fold(
        0,
        (a, t) => a + t.inputTokensMedian,
      ),
      costUsd: estimateCost(model, [for (final r in results) r.run]),
    ),
  );
}

String runReportToJson(RunReport report) =>
    const JsonEncoder.withIndent('  ').convert(report.toJson());

num _median(List<num> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// USD per million tokens, (input, output). Cache read is 0.1× and cache write
/// 1.25× the input price. Only used for the report's cost line.
const _prices = <String, (double, double)>{
  'sonnet': (3.0, 15.0),
  'haiku': (1.0, 5.0),
  'opus': (15.0, 75.0),
};

double estimateCost(String model, Iterable<AgentRun> runs) {
  final (inputPrice, outputPrice) = _prices.entries
      .firstWhere(
        (entry) => model.contains(entry.key),
        orElse: () => const MapEntry('sonnet', (3.0, 15.0)),
      )
      .value;
  var total = 0.0;
  for (final run in runs) {
    total +=
        run.inputTokens / 1e6 * inputPrice +
        run.outputTokens / 1e6 * outputPrice +
        run.cacheReadTokens / 1e6 * inputPrice * 0.1 +
        run.cacheWriteTokens / 1e6 * inputPrice * 1.25;
  }
  return total;
}

/// Thrown when two reports cannot be compared.
class CompareRefused implements Exception {
  CompareRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

class Comparison {
  Comparison(this.regressed, this.lines);
  final bool regressed;
  final List<String> lines;
}

/// Compares [current] against [baseline] (task 01 §6): a drop in the pass rate
/// or a task that passed every baseline run now failing any run regresses.
Comparison compareReports(RunReport baseline, RunReport current) {
  if (baseline.model != current.model) {
    throw CompareRefused(
      'different models: ${baseline.model} vs ${current.model}',
    );
  }
  if (baseline.device != current.device) {
    throw CompareRefused(
      'different devices: ${baseline.device} vs ${current.device}',
    );
  }
  for (final id in {...baseline.apps.keys, ...current.apps.keys}) {
    final before = baseline.apps[id]?.commit;
    final after = current.apps[id]?.commit;
    if (before != after) {
      throw CompareRefused(
        '$id is at a different commit: ${before ?? '(absent)'} vs '
        '${after ?? '(absent)'}',
      );
    }
  }

  final lines = <String>[];
  var regressed = current.totals.passRate < baseline.totals.passRate;
  lines.add(
    'pass rate: ${_pct(baseline.totals.passRate)} → '
    '${_pct(current.totals.passRate)}',
  );
  for (final id in baseline.tasks.keys) {
    final before = baseline.tasks[id]!;
    final after = current.tasks[id];
    if (after == null) {
      lines.add('$id: missing from the current run');
      continue;
    }
    if (before.pass != after.pass) {
      lines.add(
        '$id: ${before.pass}/${before.runs} → ${after.pass}/${after.runs}',
      );
    }
    if (before.pass == before.runs && after.pass < after.runs) {
      regressed = true;
    }
  }
  return Comparison(regressed, lines);
}

String _pct(double value) => '${(value * 100).toStringAsFixed(0)}%';
