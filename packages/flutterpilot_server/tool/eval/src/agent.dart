// What a run leaves behind: the calls the model made, the tokens it spent and
// its verdict. Kept behind an interface so a CLI-based runner can be added
// later without touching the scoring (task 01 §2).
import 'mcp_session.dart';
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
    this.error,
  });

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
    if (error != null) 'error': error,
  };
}

/// One task against one run, with its verdict.
class TaskRun {
  TaskRun({required this.task, required this.run, required this.passed});
  final EvalTask task;
  final AgentRun run;
  final bool passed;

  bool get isError => run.isError;
}

/// Passed: the answer matched, and the run neither errored nor ran out of turns.
bool runPassed(EvalTask task, AgentRun run) =>
    !run.isError && !run.hitTurnLimit && answerMatches(task, run.answer);

abstract class AgentRunner {
  String get model;
  Future<AgentRun> run(EvalTask task, McpClient session);
}
