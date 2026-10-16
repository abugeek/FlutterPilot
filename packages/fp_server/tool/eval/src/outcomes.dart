// Versioned run outcomes (task 04 §1).
//
// A run that never produced an answer is not the same finding as a model that
// answered wrongly. The old report counted one `pass` over every attempt, so an
// API 500 or a failed reset could hide inside a "pass rate". These outcomes keep
// the four cases apart, name the reason, and let the aggregate say honestly
// whether a benchmark is even valid: a suite with no executed cases, or one
// whose runs failed for infrastructure reasons, is not a result.
library;

/// The outcome of one task run.
enum RunOutcome {
  /// The answer matched the task's expected answer.
  passed,

  /// The run finished and the model's answer was wrong (or it never stopped
  /// calling tools and hit the turn limit). This is a finding about the model
  /// or the tool surface, not about the harness.
  failed,

  /// The run did not complete for a reason outside the model: an API or
  /// network error, the MCP server dying, or a reset that could not be
  /// trusted. It has no verdict and blocks benchmark acceptance.
  infrastructureError,

  /// The suite's spend or deadline guard stopped before this run finished.
  budgetExhausted,

  /// The case was explicitly not run (unsupported platform or capability),
  /// with a recorded reason. Skips must not be silent.
  skipped,
}

/// The version of this vocabulary. Recorded in reports so a consumer can tell
/// which set of outcome names it is reading.
const outcomesSchemaVersion = 1;

/// Whether [outcome] is a completed execution, and so belongs in the
/// correctness denominator. Infrastructure errors, skips and budget stops do
/// not.
bool outcomeExecuted(RunOutcome outcome) =>
    outcome == RunOutcome.passed || outcome == RunOutcome.failed;

/// A short human label for [outcome].
String outcomeLabel(RunOutcome outcome) => switch (outcome) {
  RunOutcome.passed => 'passed',
  RunOutcome.failed => 'failed answer',
  RunOutcome.infrastructureError => 'infrastructure error',
  RunOutcome.budgetExhausted => 'budget exhausted',
  RunOutcome.skipped => 'skipped',
};
