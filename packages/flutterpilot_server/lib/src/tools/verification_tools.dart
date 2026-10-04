part of '../../flutterpilot_server.dart';

/// Verifying a feature against acceptance criteria, with evidence
/// (ROADMAP §8): the agent drives and checks as usual; this attributes each
/// call to a criterion and writes a pass/fail report.
mixin _VerificationToolsMixin
    on
        _FlutterPilotServerBase,
        _DevtoolsToolsMixin,
        _TestGenerationToolsMixin,
        _ScenarioToolsMixin {
  Directory? _reportDir;

  /// Where each criterion's network and error lists started.
  Set<Object?> _requestIdsBefore = {};
  String _lastErrorBefore = '';

  void _registerVerificationTools() {
    _tool(
      'verify_feature',
      description:
          'Checks a feature against acceptance criteria and writes a '
          'pass/fail report with evidence. Start with feature + criteria. '
          'Then for each: criterion: N, drive the app and check it with '
          'assert_widget, wait_for or compare_screenshot. A criterion '
          'passes only if a check passed, none failed and the app threw '
          'no error; driven but unchecked is "not verified". finish:true '
          'returns the verdicts and writes '
          'flutterpilot/reports/<feature>-<time>/report.md in the app, '
          'with each criterion\'s steps, HTTP requests, errors and a '
          'screenshot.',
      inputSchema: ToolInputSchema(
        properties: {
          'feature': JsonSchema.string(description: 'What is verified.'),
          'criteria': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Acceptance criteria, one sentence each.',
          ),
          'scenario': JsonSchema.string(
            description: 'With criteria: load this scenario first.',
          ),
          'criterion': JsonSchema.integer(
            description:
                'The criterion (1-based) the next calls are evidence for; '
                'picking one again starts its evidence over.',
          ),
          'finish': JsonSchema.boolean(
            description: 'Close the last criterion and write the report.',
          ),
        },
      ),
      callback: (params, extra) async {
        final criteria = (params['criteria'] as List?)
            ?.map((c) => '$c'.trim())
            .where((c) => c.isNotEmpty)
            .toList();
        if (criteria != null) {
          return _startVerification(
            params['feature']?.toString() ?? 'Feature',
            criteria,
            params['scenario']?.toString(),
            extra,
          );
        }
        final v = _verification;
        if (v == null) {
          return _verifyError(
            'No verification running: start with feature and criteria.',
          );
        }
        if (params['criterion'] != null) {
          final n = int.tryParse('${params['criterion']}');
          if (n == null || n < 1 || n > v.criteria.length) {
            return _verifyError('criterion is 1–${v.criteria.length}.');
          }
          return _selectCriterion(v, n, extra);
        }
        if (params['finish'] == true) return _finishVerification(v, extra);
        return CallToolResult(
          content: [
            TextContent(
              text: [
                'Verifying ${v.feature}'
                    '${v.current == null ? '' : ', criterion ${v.current!.index}'}:',
                for (final c in v.criteria)
                  '${c.index}. ${c.text} — ${c.verdict.label} so far',
              ].join('\n'),
            ),
          ],
        );
      },
    );
  }

  CallToolResult _verifyError(String s) =>
      CallToolResult(isError: true, content: [TextContent(text: s)]);

  Future<CallToolResult> _startVerification(
    String feature,
    List<String> criteria,
    String? scenario,
    RequestHandlerExtra? extra,
  ) async {
    if (criteria.isEmpty) return _verifyError('Pass at least one criterion.');
    final root = await _scenarioRoot();
    if (root == null) {
      return _verifyError(
        "No running app, or its folder can't be told from its root library.",
      );
    }
    var loaded = '';
    if (scenario != null) {
      final load = _toolCallbacks['scenario'];
      if (load == null || extra == null) {
        return _verifyError('Scenarios are not available.');
      }
      final res = await load({'load': scenario}, extra);
      final text = res.content.whereType<TextContent>().map((c) => c.text);
      if (res.isError == true) {
        return _verifyError('Could not load scenario: ${text.join(' ')}');
      }
      loaded = '${text.join(' ')}\n';
    }
    final started = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final slug = feature
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    _reportDir = Directory(
      '$root/flutterpilot/reports/'
      '${slug.isEmpty ? 'feature' : slug}-${started.year}${two(started.month)}'
      '${two(started.day)}-${two(started.hour)}${two(started.minute)}',
    );
    // The requests each criterion makes come from dart:io's profile.
    await _enableHttpProfiling(const {});
    _verification = Verification(feature, criteria, started: started);
    return CallToolResult(
      content: [
        TextContent(
          text:
              '${loaded}Verifying $feature:\n'
              '${[for (var i = 0; i < criteria.length; i++) '${i + 1}. ${criteria[i]}'].join('\n')}\n'
              'Call verify_feature(criterion: 1), do the flow, check the '
              'outcome (assert_widget, wait_for, compare_screenshot); then the '
              'next criterion; verify_feature(finish: true) writes the report.',
        ),
      ],
    );
  }

  Future<CallToolResult> _selectCriterion(
    Verification v,
    int n,
    RequestHandlerExtra? extra,
  ) async {
    final previous = v.current;
    if (previous != null && previous.index != n) {
      await _closeCriterion(previous, extra);
    }
    final c = v.criteria[n - 1]..reset();
    _requestIdsBefore = {for (final r in await _httpRequests()) r['id']};
    _lastErrorBefore = (await _appErrors())
        .map((e) => '${e['timestamp']}')
        .fold('', (a, b) => b.compareTo(a) > 0 ? b : a);
    v.current = c;
    return CallToolResult(
      content: [
        TextContent(
          text:
              '${previous != null && previous.index != n ? 'Criterion ${previous.index}: ${previous.verdict.label} (${previous.reason})\n' : ''}'
              'Criterion $n: ${c.text}\nWhat you do and check now counts '
              'for it.',
        ),
      ],
    );
  }

  /// The evidence only the app has: the screen, requests and errors.
  Future<void> _closeCriterion(
    CriterionEvidence c,
    RequestHandlerExtra? extra,
  ) async {
    for (final r in await _httpRequests()) {
      if (_requestIdsBefore.contains(r['id'])) continue;
      final status = (r['response'] as Map?)?['statusCode'];
      final ms = durationMs(r);
      c.requests.add(
        '${r['method']} ${Redaction.text('${r['uri']}')} → '
        '${status ?? 'no response'}'
        '${ms == null ? '' : ' ($ms ms)'}',
      );
    }
    for (final e in await _appErrors()) {
      if ('${e['timestamp']}'.compareTo(_lastErrorBefore) <= 0) continue;
      final exception = '${e['exception']}'.split('\n').first;
      final text =
          '$exception${e['widget'] == null ? '' : ' (${e['widget']})'}';
      // What the SDK reports as a warning rather than a crash.
      if (exception.contains('RenderFlex overflowed') ||
          e['library'] == 'rendering library') {
        if (!c.warnings.contains(text)) c.warnings.add(text);
      } else {
        c.errors.add(text);
      }
    }
    final shoot = _toolCallbacks['capture_screenshot'];
    final dir = _reportDir;
    if (shoot != null && extra != null && dir != null) {
      try {
        final res = await shoot(const {}, extra);
        final image = res.content.whereType<ImageContent>().firstOrNull;
        if (image != null) {
          dir.createSync(recursive: true);
          File(
            '${dir.path}/criterion-${c.index}.png',
          ).writeAsBytesSync(base64Decode(image.data));
          c.screenshot = 'criterion-${c.index}.png';
        }
      } catch (_) {
        // A report without a picture is still a report.
      }
    }
  }

  Future<List<Map<String, dynamic>>> _httpRequests() async {
    final res = await _callExtensionRaw('ext.dart.io.getHttpProfile', {});
    return [
      for (final r in (res.data?['requests'] as List? ?? const []))
        if (r is Map<String, dynamic>) r,
    ];
  }

  Future<List<Map<String, dynamic>>> _appErrors() async {
    final res = await _callExtensionRaw('ext.flutterpilot.getErrors', {});
    return [
      for (final e in (res.data?['errors'] as List? ?? const []))
        if (e is Map<String, dynamic>) e,
    ];
  }

  Future<CallToolResult> _finishVerification(
    Verification v,
    RequestHandlerExtra? extra,
  ) async {
    final current = v.current;
    if (current != null) await _closeCriterion(current, extra);
    v.current = null;
    _verification = null;
    final dir = _reportDir!..createSync(recursive: true);
    final context = await _deviceContextForParameters(const {});
    final report = File('${dir.path}/report.md')
      ..writeAsStringSync(
        v.toMarkdown(
          app: context?.operatingSystem == null
              ? null
              : 'on ${context!.operatingSystem}',
        ),
      );
    return CallToolResult(
      content: [
        TextContent(
          text: [
            '${v.feature}: ${v.headline}.',
            for (final c in v.criteria)
              '${c.index}. ${c.verdict.label} ${c.text} — ${c.reason}',
            'Report: ${report.path} (with a screenshot per criterion).',
          ].join('\n'),
        ),
      ],
    );
  }
}
