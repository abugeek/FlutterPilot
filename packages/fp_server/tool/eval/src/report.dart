// Summaries and comparisons (task 01 §6; task 04 §1, §12–§15).
//
// A report is versioned and carries the [RunIdentity] that produced it. Counts
// are kept apart by outcome, the pass rate is over *executed* cases only, and a
// comparison refuses two reports that are not the same measurement. Cost is
// only reported when the explicit pricing table prices the model.
import 'dart:convert';

import 'agent.dart';
import 'identity.dart';
import 'outcomes.dart';
import 'pricing.dart';

/// The report schema this build writes. Version 1 is a legacy summary: no
/// identity, counts mixed, and never comparable to a version-2 report.
const reportSchemaVersion = 2;

class TaskSummary {
  TaskSummary({
    required this.passed,
    required this.failed,
    required this.errors,
    required this.budgetExhausted,
    required this.skipped,
    required this.callsMedian,
    required this.errorCallsMedian,
    required this.inputTokensMedian,
    required this.outputTokensMedian,
    required this.cacheReadTokensMedian,
    required this.secondsMedian,
    required this.toolsUsed,
    this.reasons = const [],
  });

  final int passed;
  final int failed;
  final int errors;
  final int budgetExhausted;
  final int skipped;

  /// Every attempt, whatever it ended as.
  int get runs => passed + failed + errors + budgetExhausted + skipped;

  /// Attempts that produced a verdict (passed or failed answer).
  int get executed => passed + failed;

  final num callsMedian;
  final num errorCallsMedian;
  final num inputTokensMedian;
  final num outputTokensMedian;
  final num cacheReadTokensMedian;
  final num secondsMedian;
  final Map<String, int> toolsUsed;

  /// The non-passed outcomes' reasons, deduplicated and bounded.
  final List<String> reasons;

  Map<String, Object?> toJson() => {
    'passed': passed,
    'failed': failed,
    'errors': errors,
    'budget_exhausted': budgetExhausted,
    'skipped': skipped,
    'runs': runs,
    'executed': executed,
    'calls_median': callsMedian,
    'error_calls_median': errorCallsMedian,
    'input_tokens_median': inputTokensMedian,
    'output_tokens_median': outputTokensMedian,
    'cache_read_tokens_median': cacheReadTokensMedian,
    'seconds_median': secondsMedian,
    'tools_used': toolsUsed,
    'reasons': reasons,
  };

  static TaskSummary fromJson(Map<String, dynamic> json) {
    // A legacy summary has only `pass`/`runs`; read it as passed cases.
    final passed = (json['passed'] ?? json['pass'] ?? 0) as int;
    final runs = (json['runs'] ?? passed) as int;
    return TaskSummary(
      passed: passed,
      failed: (json['failed'] ?? (runs - passed)) as int,
      errors: (json['errors'] ?? 0) as int,
      budgetExhausted: (json['budget_exhausted'] ?? 0) as int,
      skipped: (json['skipped'] ?? 0) as int,
      callsMedian: json['calls_median'] as num,
      errorCallsMedian: json['error_calls_median'] as num,
      inputTokensMedian: json['input_tokens_median'] as num,
      outputTokensMedian: json['output_tokens_median'] as num,
      cacheReadTokensMedian: json['cache_read_tokens_median'] as num,
      secondsMedian: json['seconds_median'] as num,
      toolsUsed: (json['tools_used'] as Map).cast<String, int>(),
      reasons: [for (final r in (json['reasons'] as List? ?? const [])) '$r'],
    );
  }
}

class AppInfo {
  AppInfo({
    required this.commit,
    required this.toolsListed,
    required this.toolListChars,
    required this.toolListUtf8Bytes,
    this.guidanceHash = '',
    this.toolSchemaHash = '',
    this.protocol = '',
  });

  final String commit;
  final int toolsListed;

  /// The legacy character measure (`toolListChars`); the field the old
  /// summaries recorded as `tool_list_bytes`.
  final int toolListChars;

  /// UTF-8 bytes of the same model-facing projection.
  final int toolListUtf8Bytes;

  /// sha256 of the server's `initialize` instructions.
  final String guidanceHash;

  /// sha256 of the model-facing tool projection (see
  /// [canonicalToolSchemaHash]). Expected to differ between a baseline and the
  /// change under test — reported, not rejected.
  final String toolSchemaHash;

  /// The protocol version the session negotiated.
  final String protocol;

  Map<String, Object?> toJson() => {
    'commit': commit,
    'tools_listed': toolsListed,
    'tool_list_chars': toolListChars,
    'tool_list_utf8_bytes': toolListUtf8Bytes,
    'tool_list_bytes': toolListChars, // legacy alias; read on load
    'guidance_hash': guidanceHash,
    'tool_schema_hash': toolSchemaHash,
    'protocol': protocol,
  };

  static AppInfo fromJson(Map<String, dynamic> json) => AppInfo(
    commit: '${json['commit']}',
    toolsListed: json['tools_listed'] as int,
    // Older summaries wrote only `tool_list_bytes` (the same measure).
    toolListChars: (json['tool_list_chars'] ?? json['tool_list_bytes']) as int,
    toolListUtf8Bytes:
        (json['tool_list_utf8_bytes'] ?? json['tool_list_bytes']) as int,
    guidanceHash: '${json['guidance_hash'] ?? ''}',
    toolSchemaHash: '${json['tool_schema_hash'] ?? ''}',
    protocol: '${json['protocol'] ?? ''}',
  );
}

class Totals {
  Totals({
    required this.passed,
    required this.failed,
    required this.errors,
    required this.budgetExhausted,
    required this.skipped,
    required this.passRate,
    required this.callsMedianSum,
    required this.inputTokensMedianSum,
    required this.costUsd,
    required this.costKnown,
  });

  final int passed;
  final int failed;
  final int errors;
  final int budgetExhausted;
  final int skipped;

  int get runs => passed + failed + errors + budgetExhausted + skipped;
  int get executed => passed + failed;

  /// Pass rate over executed cases only: an infrastructure error or a skip is
  /// not a wrong answer, and must not move the rate.
  final double passRate;
  final num callsMedianSum;
  final num inputTokensMedianSum;

  /// Estimated USD, meaningful only when [costKnown].
  final double costUsd;
  final bool costKnown;

  /// A benchmark is only a result when at least one case executed, no run hit
  /// an infrastructure error, and no run was stopped by a budget guard.
  /// Failed answers are a finding, not a broken benchmark. (Skips are allowed
  /// here only because a skip of every case leaves [executed] at zero.)
  bool get benchmarkValid =>
      executed > 0 && errors == 0 && budgetExhausted == 0;

  Map<String, Object?> toJson() => {
    'passed': passed,
    'failed': failed,
    'errors': errors,
    'budget_exhausted': budgetExhausted,
    'skipped': skipped,
    'runs': runs,
    'executed': executed,
    'pass_rate': passRate,
    'calls_median_sum': callsMedianSum,
    'input_tokens_median_sum': inputTokensMedianSum,
    'cost_usd': costKnown ? costUsd : null,
    'cost_known': costKnown,
    'benchmark_valid': benchmarkValid,
  };

  static Totals fromJson(Map<String, dynamic> json) {
    final passed = (json['passed'] ?? json['pass'] ?? 0) as int;
    final runs = (json['runs'] ?? passed) as int;
    final costKnown = json['cost_known'] as bool? ?? json['cost_usd'] != null;
    return Totals(
      passed: passed,
      failed: (json['failed'] ?? (runs - passed)) as int,
      errors: (json['errors'] ?? 0) as int,
      budgetExhausted: (json['budget_exhausted'] ?? 0) as int,
      skipped: (json['skipped'] ?? 0) as int,
      passRate: ((json['pass_rate'] as num?) ?? 0).toDouble(),
      callsMedianSum: (json['calls_median_sum'] as num?) ?? 0,
      inputTokensMedianSum: (json['input_tokens_median_sum'] as num?) ?? 0,
      costUsd: ((json['cost_usd'] as num?) ?? 0).toDouble(),
      costKnown: costKnown,
    );
  }
}

class RunReport {
  RunReport({
    required this.model,
    required this.device,
    required this.serverCommit,
    required this.apps,
    required this.tasks,
    required this.totals,
    required this.identity,
    this.schemaVersion = reportSchemaVersion,
  });

  final int schemaVersion;
  final String model;
  final String device;
  final String serverCommit;
  final Map<String, AppInfo> apps;
  final Map<String, TaskSummary> tasks;
  final Totals totals;

  /// What produced the run, or null for a legacy summary.
  final RunIdentity? identity;

  /// True for a summary written before version 2: it has no identity and must
  /// not be treated as equivalent evidence (task 04 §12–§13).
  bool get legacy => schemaVersion < reportSchemaVersion || identity == null;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'outcomes_schema_version': outcomesSchemaVersion,
    'model': model,
    'device': device,
    'server_commit': serverCommit,
    'identity': identity?.toJson(),
    'apps': {for (final e in apps.entries) e.key: e.value.toJson()},
    'tasks': {for (final e in tasks.entries) e.key: e.value.toJson()},
    'totals': totals.toJson(),
  };

  static RunReport fromJson(Map<String, dynamic> json) {
    final version = (json['schemaVersion'] as int?) ?? 1;
    final identityJson = json['identity'];
    return RunReport(
      schemaVersion: version,
      model: '${json['model']}',
      device: '${json['device']}',
      serverCommit: '${json['server_commit']}',
      identity: version >= reportSchemaVersion && identityJson is Map
          ? RunIdentity.fromJson(identityJson.cast<String, dynamic>())
          : null,
      apps: {
        for (final e in (json['apps'] as Map).entries)
          '${e.key}': AppInfo.fromJson(
            (e.value as Map).cast<String, dynamic>(),
          ),
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
}

/// Aggregates one suite's runs into [RunReport] (counts per outcome, medians
/// per task, a total). Cost is computed with the explicit [pricing] table and
/// is `known: false` when the model is unpriced.
RunReport summarize({
  required String model,
  required String device,
  required String serverCommit,
  required Map<String, AppInfo> apps,
  required List<TaskRun> results,
  required RunIdentity identity,
  PricingConfig pricing = PricingConfig.empty,
}) {
  final byTask = <String, List<TaskRun>>{};
  for (final result in results) {
    byTask.putIfAbsent(result.task.id, () => []).add(result);
  }

  int count(RunOutcome outcome, List<TaskRun> list) =>
      list.where((r) => r.outcome == outcome).length;

  final tasks = <String, TaskSummary>{};
  for (final entry in byTask.entries) {
    final list = entry.value;
    final toolsUsed = <String, int>{};
    for (final result in list) {
      for (final call in result.run.calls) {
        toolsUsed[call.name] = (toolsUsed[call.name] ?? 0) + 1;
      }
    }
    final reasons = <String>[];
    for (final result in list) {
      final reason = result.reason ?? result.run.error;
      if (result.outcome != RunOutcome.passed &&
          reason != null &&
          reason.isNotEmpty &&
          !reasons.contains(reason)) {
        reasons.add(reason);
      }
    }
    tasks[entry.key] = TaskSummary(
      passed: count(RunOutcome.passed, list),
      failed: count(RunOutcome.failed, list),
      errors: count(RunOutcome.infrastructureError, list),
      budgetExhausted: count(RunOutcome.budgetExhausted, list),
      skipped: count(RunOutcome.skipped, list),
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
      reasons: reasons.take(20).toList(),
    );
  }

  var passed = 0;
  var failed = 0;
  var errors = 0;
  var budgetExhausted = 0;
  var skipped = 0;
  for (final result in results) {
    switch (result.outcome) {
      case RunOutcome.passed:
        passed++;
      case RunOutcome.failed:
        failed++;
      case RunOutcome.infrastructureError:
        errors++;
      case RunOutcome.budgetExhausted:
        budgetExhausted++;
      case RunOutcome.skipped:
        skipped++;
    }
  }
  final executed = passed + failed;
  final cost = estimateCost(model, [for (final r in results) r.run], pricing);

  return RunReport(
    model: model,
    device: device,
    serverCommit: serverCommit,
    identity: identity,
    apps: apps,
    tasks: Map.fromEntries(
      tasks.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
    totals: Totals(
      passed: passed,
      failed: failed,
      errors: errors,
      budgetExhausted: budgetExhausted,
      skipped: skipped,
      passRate: executed == 0 ? 0 : passed / executed,
      callsMedianSum: tasks.values.fold(0, (a, t) => a + t.callsMedian),
      inputTokensMedianSum: tasks.values.fold(
        0,
        (a, t) => a + t.inputTokensMedian,
      ),
      costUsd: cost.usd,
      costKnown: cost.known,
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

/// Thrown when two reports cannot be compared.
class CompareRefused implements Exception {
  CompareRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

class Comparison {
  Comparison(this.regressed, this.lines, {this.incomplete = false});
  final bool regressed;
  final bool incomplete;
  final List<String> lines;
}

/// Compares [current] against [baseline] (task 01 §6; task 04 §13–§15).
///
/// Refuses a legacy summary or a different measurement. A missing task,
/// infrastructure error, budget stop or skip on either side makes the
/// comparison [Comparison.incomplete] — and a pass-rate drop or a task that
/// passed every baseline run now failing [Comparison.regressed].
Comparison compareReports(RunReport baseline, RunReport current) {
  if (baseline.legacy || current.legacy) {
    throw CompareRefused(
      'a legacy summary has no run identity and cannot be compared; '
      're-run the baseline with this runner',
    );
  }
  if (baseline.schemaVersion != current.schemaVersion) {
    throw CompareRefused(
      'different report schema versions: '
      '${baseline.schemaVersion} vs ${current.schemaVersion}',
    );
  }
  final mismatches = baseline.identity!.hardMismatches(current.identity!);
  if (mismatches.isNotEmpty) {
    throw CompareRefused(mismatches.join('; '));
  }

  final lines = <String>[];
  var incomplete = false;

  for (final id in {...baseline.apps.keys, ...current.apps.keys}) {
    final before = baseline.apps[id];
    final after = current.apps[id];
    if (before == null || after == null) {
      throw CompareRefused('$id is present in only one run');
    }
    // The app (fixture) revision must match; a changed fixture is a different
    // measurement.
    if (before.commit != after.commit) {
      throw CompareRefused(
        '$id is at a different commit: ${before.commit} vs ${after.commit}',
      );
    }
    // The server's guidance and tool schema are expected to differ between a
    // baseline and the change under test: report, don't reject.
    if (before.toolSchemaHash != after.toolSchemaHash) {
      lines.add(
        '$id tool schema changed '
        '(${before.toolsListed} → ${after.toolsListed} tools)',
      );
    }
    if (before.guidanceHash != after.guidanceHash) {
      lines.add('$id guidance changed');
    }
  }
  if (baseline.serverCommit != current.serverCommit) {
    lines.add(
      'server commit: ${baseline.serverCommit} → '
      '${current.serverCommit}',
    );
  }
  for (final line in baseline.identity!.expectedDifferences(
    current.identity!,
  )) {
    lines.add(line);
  }

  for (final (label, report) in [
    ('baseline', baseline),
    ('current', current),
  ]) {
    final totals = report.totals;
    if (totals.errors > 0) {
      incomplete = true;
      lines.add('$label has ${totals.errors} infrastructure error(s)');
    }
    if (totals.budgetExhausted > 0) {
      incomplete = true;
      lines.add(
        '$label stopped ${totals.budgetExhausted} run(s) on a budget guard',
      );
    }
    if (totals.skipped > 0) {
      incomplete = true;
      lines.add('$label skipped ${totals.skipped} run(s) without approval');
    }
  }

  var regressed = false;
  if (baseline.totals.executed > 0 && current.totals.executed > 0) {
    if (current.totals.passRate < baseline.totals.passRate) regressed = true;
    lines.add(
      'pass rate (executed): ${_pct(baseline.totals.passRate)} → '
      '${_pct(current.totals.passRate)}',
    );
  }
  for (final id in baseline.tasks.keys) {
    final before = baseline.tasks[id]!;
    final after = current.tasks[id];
    if (after == null) {
      incomplete = true;
      lines.add('$id: missing from the current run');
      continue;
    }
    if (before.executed != after.executed || before.passed != after.passed) {
      lines.add(
        '$id: ${before.passed}/${before.executed} → '
        '${after.passed}/${after.executed}',
      );
    }
    if (before.executed > 0 &&
        before.passed == before.executed &&
        after.passed < after.executed) {
      regressed = true;
    }
  }
  for (final id in current.tasks.keys) {
    if (!baseline.tasks.containsKey(id)) {
      incomplete = true;
      lines.add('$id: new in the current run');
    }
  }

  // Then the costs of getting there (task 04 §15): calls, errors, tokens,
  // time and cost, with the sample size so a small repeat reads as screening.
  num sum(RunReport report, num Function(TaskSummary) pick) =>
      report.tasks.values.fold(0, (a, t) => a + pick(t));
  lines.add(
    'calls (median sum): ${baseline.totals.callsMedianSum} → '
    '${current.totals.callsMedianSum}',
  );
  lines.add(
    'error calls (median sum): ${sum(baseline, (t) => t.errorCallsMedian)} → '
    '${sum(current, (t) => t.errorCallsMedian)}',
  );
  lines.add(
    'input tokens (median sum): ${baseline.totals.inputTokensMedianSum} → '
    '${current.totals.inputTokensMedianSum}',
  );
  lines.add(
    'output tokens (median sum): '
    '${sum(baseline, (t) => t.outputTokensMedian)} → '
    '${sum(current, (t) => t.outputTokensMedian)}',
  );
  lines.add(
    'cache-read tokens (median sum): '
    '${sum(baseline, (t) => t.cacheReadTokensMedian)} → '
    '${sum(current, (t) => t.cacheReadTokensMedian)}',
  );
  lines.add(
    'seconds (median sum): ${sum(baseline, (t) => t.secondsMedian)} → '
    '${sum(current, (t) => t.secondsMedian)}',
  );
  if (baseline.totals.costKnown && current.totals.costKnown) {
    lines.add(
      'cost: \$${baseline.totals.costUsd.toStringAsFixed(4)} → '
      '\$${current.totals.costUsd.toStringAsFixed(4)}',
    );
  } else {
    lines.add('cost: unknown (no explicit price for the model)');
  }
  final repeat = baseline.identity!.policy['repeat'];
  lines.add(
    'sample: ${baseline.totals.executed} baseline / '
    '${current.totals.executed} current case(s) '
    '(repeat $repeat); small repeats are screening, not proof',
  );

  return Comparison(regressed, lines, incomplete: incomplete);
}

String _pct(double value) => '${(value * 100).toStringAsFixed(0)}%';
