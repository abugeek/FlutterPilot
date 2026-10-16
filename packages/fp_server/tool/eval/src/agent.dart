// What a run leaves behind: the calls the model made, the tokens it spent and
// its verdict. Kept behind an interface so a CLI-based runner can be added
// later without touching the scoring (task 01 §2).
import 'mcp_session.dart';
import 'outcomes.dart';
import 'tasks.dart';

class ToolCallRecord {
  ToolCallRecord(this.name, this.milliseconds, this.isError, this.chars);
  final String name;
  final int milliseconds;
  final bool isError;
  final int chars;

  Map<String, Object?> toJson() => {
    'name': name,
    'ms': milliseconds,
    'isError': isError,
    'chars': chars,
  };
}

class AgentRun {
  AgentRun({
    required this.calls,
    required this.turns,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheWriteTokens,
    required this.cacheReadTokens,
    required this.seconds,
    required this.finalText,
    required this.hitTurnLimit,
    this.hitCallLimit = false,
    this.error,
  });

  /// A run that never started (a reset failure, a budget stop, a skip): no
  /// calls, no tokens, and — when [error] is given — an infrastructure error.
  factory AgentRun.empty({String? error}) => AgentRun(
    calls: const [],
    turns: 0,
    inputTokens: 0,
    outputTokens: 0,
    cacheWriteTokens: 0,
    cacheReadTokens: 0,
    seconds: 0,
    finalText: '',
    hitTurnLimit: false,
    error: error,
  );

  final List<ToolCallRecord> calls;
  final int turns;
  final int inputTokens;
  final int outputTokens;
  final int cacheWriteTokens;
  final int cacheReadTokens;
  final double seconds;
  final String finalText;

  /// The model kept calling tools until the limit instead of answering.
  final bool hitTurnLimit;

  /// The run reached its hard call cap (`--max-calls`) before answering.
  final bool hitCallLimit;

  /// A non-null message when the run failed for infrastructure reasons
  /// (network, API), never when the model simply got the answer wrong.
  final String? error;

  String? get answer => extractAnswer(finalText);
  bool get isError => error != null;
  int get errorCalls => calls.where((call) => call.isError).length;

  Map<String, Object?> toJson() => {
    'turns': turns,
    'calls': [for (final call in calls) call.toJson()],
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheWriteTokens': cacheWriteTokens,
    'cacheReadTokens': cacheReadTokens,
    'seconds': seconds,
    'finalText': finalText,
    'answer': answer,
    'hitTurnLimit': hitTurnLimit,
    'hitCallLimit': hitCallLimit,
    if (error != null) 'error': error,
  };
}

/// One task against one run, with its verdict and a versioned outcome.
class TaskRun {
  TaskRun({
    required this.task,
    required this.run,
    required this.passed,
    RunOutcome? outcome,
    this.reason,
  }) : outcome = outcome ?? _derive(passed, run);

  /// A case that was explicitly not run, with [reason] (task 04 §1).
  TaskRun.skipped(EvalTask task, String reason)
    : this(
        task: task,
        run: AgentRun.empty(),
        passed: false,
        outcome: RunOutcome.skipped,
        reason: reason,
      );

  /// A case the spend or deadline guard stopped before it ran.
  TaskRun.budget(EvalTask task, String reason)
    : this(
        task: task,
        run: AgentRun.empty(),
        passed: false,
        outcome: RunOutcome.budgetExhausted,
        reason: reason,
      );

  final EvalTask task;
  final AgentRun run;
  final bool passed;

  /// The versioned outcome ([RunOutcome]); from [passed] and [run] unless a
  /// caller (a skip, a budget stop) set it directly.
  final RunOutcome outcome;

  /// Why [outcome] is what it is, when that needs saying (a skip reason).
  final String? reason;

  bool get isError => run.isError;

  static RunOutcome _derive(bool passed, AgentRun run) {
    if (run.error != null) return RunOutcome.infrastructureError;
    return passed ? RunOutcome.passed : RunOutcome.failed;
  }
}

/// Passed: the answer matched, and the run neither errored, ran out of turns,
/// nor hit its call cap.
bool runPassed(EvalTask task, AgentRun run) =>
    !run.isError &&
    !run.hitTurnLimit &&
    !run.hitCallLimit &&
    answerMatches(task, run.answer);

abstract class AgentRunner {
  String get model;
  Future<AgentRun> run(EvalTask task, McpClient session);
}
