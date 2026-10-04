/// Verifying a feature against acceptance criteria (ROADMAP §8): what the
/// agent did and checked for each criterion, and a verdict that only
/// evidence can make a pass.
class Verification {
  Verification(this.feature, List<String> criteria, {DateTime? started})
    : started = started ?? DateTime.now(),
      criteria = [
        for (var i = 0; i < criteria.length; i++)
          CriterionEvidence(i + 1, criteria[i]),
      ];

  final String feature;
  final DateTime started;
  final List<CriterionEvidence> criteria;

  /// The criterion tool calls count towards; null before the agent picks.
  CriterionEvidence? current;

  /// Tools that change the app, and tools that check it.
  static const actions = {
    'tap_widget',
    'enter_text',
    'press_key',
    'fill_form',
    'execute_action_chain',
    'scroll_into_view',
    'swipe_widget',
    'drag_widget',
    'toggle_checkbox',
    'set_slider_value',
    'focus_widget',
    'pinch_zoom',
    'navigate_to',
    'mock_http_response',
    'mock_platform_channel',
    'simulate_network',
    'set_state',
    'set_shared_preference',
    'set_app_settings',
    'hot_reload',
    'scenario',
    'native_tap',
    'native_text',
    'native_button',
    'native_open_app',
    'call_custom_tool',
  };
  static const checks = {'assert_widget', 'wait_for', 'compare_screenshot'};

  /// Records a finished tool call against the current criterion.
  void record(
    String tool,
    Map<String, dynamic> args,
    String resultText, {
    required bool isError,
  }) {
    final c = current;
    if (c == null) return;
    final isCheck = checks.contains(tool);
    if (!isCheck && !actions.contains(tool)) return;
    c.steps.add(
      StepEvidence(
        tool: tool,
        // Checks show what was asserted; actions show their response,
        // which already masks what was typed into password fields.
        what: isCheck ? _describeArgs(args) : null,
        result: _firstLine(resultText),
        isError: isError,
        isCheck: isCheck,
      ),
    );
  }

  static String _describeArgs(Map<String, dynamic> args) => args.entries
      .where((e) => e.value != null && e.key != 'timeoutMs')
      .map((e) => '${e.key}: ${e.value is String ? '"${e.value}"' : e.value}')
      .join(', ');

  /// The response's first line, without the error category and the
  /// advice meant for the agent.
  static String _firstLine(String text) {
    var line = text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '')
        .replaceFirst(RegExp(r'^\[\w+\] '), '');
    if (line.startsWith('{"status":"passed"')) return 'passed';
    for (final advice in [' Nothing changed in', ' If it starts', ' HINT:']) {
      final i = line.indexOf(advice);
      if (i > 0) line = line.substring(0, i);
    }
    return line.length > 200 ? '${line.substring(0, 200)}…' : line;
  }

  int count(Verdict v) => criteria.where((c) => c.verdict == v).length;

  String get headline {
    final passed = count(Verdict.pass);
    final failed = count(Verdict.fail);
    final unverified = count(Verdict.unverified);
    final overall = failed > 0
        ? 'FAILED'
        : unverified > 0
        ? 'INCOMPLETE'
        : 'PASSED';
    return '$overall: $passed of ${criteria.length} criteria passed'
        '${failed > 0 ? ', $failed failed' : ''}'
        '${unverified > 0 ? ', $unverified not verified' : ''}';
  }

  /// The report, Markdown with the screenshots next to it.
  String toMarkdown({String? app}) {
    final b = StringBuffer()
      ..writeln('# Verification: $feature')
      ..writeln()
      ..writeln(
        '${_stamp(started)}${app == null ? '' : ' · $app'} · **$headline**',
      )
      ..writeln()
      ..writeln('| # | Criterion | Result |')
      ..writeln('|---|---|---|');
    for (final c in criteria) {
      b.writeln('| ${c.index} | ${_cell(c.text)} | ${c.verdict.label} |');
    }
    for (final c in criteria) {
      b
        ..writeln()
        ..writeln('## ${c.index}. ${c.text} — ${c.verdict.label}')
        ..writeln()
        ..writeln('_${c.reason}_');
      if (c.steps.isNotEmpty) {
        b
          ..writeln()
          ..writeln('Steps:');
        for (final (i, s) in c.steps.indexed) {
          final mark = s.isError ? '❌ ' : (s.isCheck ? '✔ ' : '');
          b.writeln(
            '${i + 1}. $mark`${s.tool}`${s.what == null ? '' : ' (${s.what})'}'
            ' → ${s.result}',
          );
        }
      }
      if (c.requests.isNotEmpty) {
        b
          ..writeln()
          ..writeln('Network:');
        for (final r in c.requests.take(15)) {
          b.writeln('- $r');
        }
        if (c.requests.length > 15) {
          final rest = c.requests.skip(15);
          final failed = rest.where(
            (r) => RegExp(r'→ ([45]\d\d|no response)').hasMatch(r),
          );
          b.writeln(
            '- … and ${rest.length} more'
            '${failed.isEmpty ? '' : ' (${failed.length} of them failed)'}',
          );
        }
      }
      if (c.errors.isNotEmpty) {
        b
          ..writeln()
          ..writeln('Errors:');
        for (final e in c.errors) {
          b.writeln('- $e');
        }
      }
      if (c.warnings.isNotEmpty) {
        b
          ..writeln()
          ..writeln('Warnings (not counted against it):');
        for (final w in c.warnings) {
          b.writeln('- $w');
        }
      }
      if (c.screenshot != null) {
        b
          ..writeln()
          ..writeln('![Screen after criterion ${c.index}](${c.screenshot})');
      }
    }
    return b.toString();
  }

  static String _cell(String s) => s.replaceAll('|', r'\|');

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}

enum Verdict {
  pass('✅ PASS'),
  fail('❌ FAIL'),
  unverified('⚠️ NOT VERIFIED');

  const Verdict(this.label);
  final String label;
}

class CriterionEvidence {
  CriterionEvidence(this.index, this.text);

  final int index;
  final String text;
  final steps = <StepEvidence>[];
  final requests = <String>[];
  final errors = <String>[];

  /// Layout overflows and the like: shown, but not failing the criterion.
  final warnings = <String>[];
  String? screenshot;

  /// Where the network and error lists stood when the criterion began.
  int requestsBefore = 0;
  int errorsBefore = 0;

  /// Starting the criterion again (the agent got it wrong) replaces its
  /// evidence.
  void reset() {
    steps.clear();
    requests.clear();
    errors.clear();
    warnings.clear();
    screenshot = null;
  }

  Iterable<StepEvidence> get _checks => steps.where((s) => s.isCheck);

  /// A pass needs a passing check and nothing against it: the agent's own
  /// say-so is not evidence.
  Verdict get verdict {
    if (errors.isNotEmpty || _checks.any((s) => s.isError)) {
      return Verdict.fail;
    }
    if (_checks.isEmpty) return Verdict.unverified;
    return Verdict.pass;
  }

  String get reason {
    final failed = _checks.where((s) => s.isError).toList();
    if (failed.isNotEmpty) {
      final check = failed.first;
      // An action that failed before it is the likelier cause.
      final action = steps
          .take(steps.indexOf(check))
          .where((s) => !s.isCheck && s.isError)
          .firstOrNull;
      return 'Check failed: `${check.tool}` (${check.what}) → ${check.result}'
          '${action == null ? '' : '. Before it `${action.tool}` failed: ${action.result}'}';
    }
    if (errors.isNotEmpty) {
      return 'The app threw ${errors.length} error(s) meanwhile.';
    }
    if (_checks.isEmpty) {
      return steps.isEmpty
          ? 'Nothing was done or checked for it.'
          : 'Driven but never checked: no assert_widget, wait_for or '
                'compare_screenshot passed.';
    }
    return '${_checks.length} check(s) passed, no errors.';
  }
}

class StepEvidence {
  StepEvidence({
    required this.tool,
    required this.what,
    required this.result,
    required this.isError,
    required this.isCheck,
  });

  final String tool;
  final String? what;
  final String result;
  final bool isError;
  final bool isCheck;
}
