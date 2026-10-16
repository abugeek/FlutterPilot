// Tests for the eval runner (task 01 §Tests). They run without a key: the
// Messages API is a local HttpServer returning scripted responses, and the MCP
// session is a fake. The point of these is the loop's shape (tool_use ->
// tool_result, images, is_error, turn limit, retry, a refreshed tool list),
// scoring, aggregation, comparison and that the key is never written anywhere.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../tool/eval/src/agent.dart';
import '../tool/eval/src/anthropic_runner.dart';
import '../tool/eval/src/identity.dart';
import '../tool/eval/src/mcp_session.dart';
import '../tool/eval/src/policy.dart';
import '../tool/eval/src/pricing.dart';
import '../tool/eval/src/report.dart';
import '../tool/eval/src/tasks.dart';
import 'package:test/test.dart';

const _sentinelKey = 'sk-ant-SENTINEL-never-write-me';

EvalTask _task({
  String id = 'shop_count',
  String answer = '42',
  MatchMode match = MatchMode.exact,
}) => EvalTask(
  id: id,
  app: 'fp_lab_shop',
  prompt: 'How many?',
  answer: answer,
  match: match,
);

McpTool _tool(String name) => McpTool({
  'name': name,
  'description': 'does $name',
  'inputSchema': {'type': 'object'},
});

/// A scripted Messages API: each reply is a Map (200 + JSON) or an int (that
/// status with a small error body). Records every request body.
class FakeApi {
  FakeApi(this._replies);
  final List<Object> _replies;
  final List<Map<String, dynamic>> received = [];
  HttpServer? _server;

  int get port => _server!.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      received.add(jsonDecode(body) as Map<String, dynamic>);
      final reply = _replies.removeAt(0);
      request.response.headers.contentType = ContentType.json;
      if (reply is int) {
        request.response.statusCode = reply;
        request.response.write('{"error":{"type":"overloaded"}}');
      } else {
        request.response.write(jsonEncode(reply));
      }
      await request.response.close();
    });
  }

  Future<void> stop() async => _server?.close(force: true);
}

Map<String, dynamic> _textReply(String text, {String stop = 'end_turn'}) => {
  'id': 'msg',
  'type': 'message',
  'role': 'assistant',
  'model': 'fake',
  'content': [
    {'type': 'text', 'text': text},
  ],
  'stop_reason': stop,
  'usage': {'input_tokens': 10, 'output_tokens': 5},
};

Map<String, dynamic> _toolUseReply(String name, Map<String, dynamic> input) => {
  'id': 'msg',
  'type': 'message',
  'role': 'assistant',
  'model': 'fake',
  'content': [
    {'type': 'tool_use', 'id': 'tu1', 'name': name, 'input': input},
  ],
  'stop_reason': 'tool_use',
  'usage': {'input_tokens': 10, 'output_tokens': 5},
};

class FakeMcp implements McpClient {
  FakeMcp({this.instructions = 'TEST INSTRUCTIONS', List<McpTool>? tools})
    : _tools = tools ?? [];
  @override
  String instructions;
  List<McpTool> _tools;
  @override
  List<McpTool> get tools => _tools;
  final _changes = StreamController<List<McpTool>>.broadcast();
  @override
  Stream<List<McpTool>> get toolListChanges => _changes.stream;

  final List<String> called = [];
  McpCallResult Function(String name)? onCall;

  @override
  Future<McpCallResult> call(
    String name, [
    Map<String, dynamic>? arguments,
  ]) async {
    called.add(name);
    return onCall?.call(name) ??
        McpCallResult(
          [
            {'type': 'text', 'text': 'ok'},
          ],
          false,
          5,
          2,
        );
  }

  void pushTools(List<McpTool> tools) {
    _tools = tools;
    _changes.add(tools);
  }

  void dispose() => _changes.close();
}

AnthropicRunner _runner(FakeApi api, {int maxTurns = 40}) => AnthropicRunner(
  apiKey: _sentinelKey,
  model: 'test-model',
  maxTurns: maxTurns,
  baseUrl: 'http://127.0.0.1:${api.port}',
);

/// A minimal identity both sides of a test comparison can share. Pass a
/// different [model]/[device] to exercise a refusal.
RunIdentity _identity({
  String model = 'test-model',
  String device = 'windows',
  List<String> ids = const ['shop_count'],
  Map<String, Object?> policy = const {'repeat': 3},
}) => RunIdentity(
  model: model,
  device: device,
  platform: 'windows',
  taskSuite: TaskSuiteIdentity(hash: 'suite-hash', ids: ids),
  policy: policy,
);

/// An explicit price for `test-model`: $3/M input, $15/M output, $0.30/M cache
/// read, $3.75/M cache write.
const _priced = PricingConfig(
  version: 1,
  asOf: '2026-01-01',
  currency: 'USD',
  models: {
    'test-model': ModelPrice(
      inputPerMTok: 3,
      outputPerMTok: 15,
      cacheReadPerMTok: 0.3,
      cacheWritePerMTok: 3.75,
    ),
  },
);

/// [reply] with extra usage fields merged in.
Map<String, dynamic> _usage(
  Map<String, dynamic> reply,
  Map<String, int> extra,
) => {
  ...reply,
  'usage': {...(reply['usage'] as Map).cast<String, dynamic>(), ...extra},
};

void main() {
  group('answer extraction and matching', () {
    test('the last ANSWER wins; a missing one is null', () {
      expect(extractAnswer('thinking\nANSWER: one\nmore\nANSWER: two'), 'two');
      expect(
        extractAnswer('answer: lower case works too'),
        'lower case works too',
      );
      expect(extractAnswer('no answer here'), isNull);
      expect(extractAnswer('ANSWER:   '), isNull);
    });

    test('exact, regex and number modes', () {
      final exact = _task(answer: '/checkout');
      expect(answerMatches(exact, '/checkout'), isTrue);
      expect(answerMatches(exact, '  /ChecKout '), isTrue);
      expect(answerMatches(exact, '/cart'), isFalse);
      expect(answerMatches(exact, null), isFalse);

      final number = _task(answer: '250', match: MatchMode.number);
      expect(answerMatches(number, '250'), isTrue);
      expect(answerMatches(number, '250.0'), isTrue);
      expect(answerMatches(number, '2'), isFalse);
      expect(answerMatches(number, 'not a number'), isFalse);

      final regex = _task(
        answer: r'lib/[a-z_/]+\.dart:25',
        match: MatchMode.regex,
      );
      expect(answerMatches(regex, 'lib/widgets/product_card.dart:25'), isTrue);
      expect(
        answerMatches(regex, 'see lib/widgets/product_card.dart:25'),
        isFalse,
      );
    });

    test('a turn-limit or errored run never counts as passed', () {
      final task = _task(answer: '42');
      final ok = _run(text: 'ANSWER: 42');
      expect(runPassed(task, ok), isTrue);
      expect(
        runPassed(task, _run(text: 'ANSWER: 42', turnLimit: true)),
        isFalse,
      );
      expect(runPassed(task, _run(text: 'ANSWER: 42', error: true)), isFalse);
    });
  });

  group('agent loop', () {
    test('runs a tool, sends the result back and stops on end_turn', () async {
      final mcp = FakeMcp(tools: [_tool('get_app_summary')]);
      mcp.onCall = (_) => McpCallResult(
        [
          {'type': 'text', 'text': 'summary text'},
        ],
        false,
        7,
        12,
      );
      final api = FakeApi([
        _toolUseReply('get_app_summary', {}),
        _textReply('done\nANSWER: 42'),
      ]);
      await api.start();
      addTearDown(api.stop);
      addTearDown(mcp.dispose);

      final run = await _runner(api).run(_task(), mcp);

      expect(run.turns, 2);
      expect(run.calls.map((c) => c.name), ['get_app_summary']);
      expect(run.answer, '42');
      expect(run.inputTokens, 20, reason: 'two turns of usage add up');
      expect(api.received, hasLength(2));

      final first = api.received.first;
      expect((first['tools'] as List).first['name'], 'get_app_summary');
      expect((first['tools'] as List).first['input_schema'], {
        'type': 'object',
      });
      expect((first['system'] as List).first['text'], 'TEST INSTRUCTIONS');
      // Prompt caching is preserved (task 04 §10): a breakpoint on the system
      // block and one on the last tool.
      expect((first['system'] as List).first['cache_control'], {
        'type': 'ephemeral',
      });
      expect((first['tools'] as List).last['cache_control'], {
        'type': 'ephemeral',
      });

      final followUp = api.received[1]['messages'] as List;
      final toolResult = (followUp.last['content'] as List).first;
      expect(toolResult['type'], 'tool_result');
      expect(toolResult['content'][0]['text'], 'summary text');
    });

    test('images become image blocks and is_error is set', () async {
      final mcp = FakeMcp(tools: [_tool('capture_screenshot')]);
      mcp.onCall = (_) => McpCallResult(
        [
          {'type': 'text', 'text': 'shot'},
          {'type': 'image', 'mimeType': 'image/png', 'data': 'QUJD'},
        ],
        true,
        3,
        9,
      );
      final api = FakeApi([
        _toolUseReply('capture_screenshot', {}),
        _textReply('ANSWER: ok'),
      ]);
      await api.start();
      addTearDown(api.stop);
      addTearDown(mcp.dispose);

      await _runner(api).run(_task(), mcp);

      final toolResult =
          ((api.received[1]['messages'] as List).last['content'] as List).first;
      expect(toolResult['is_error'], isTrue);
      expect(toolResult['content'][1]['type'], 'image');
      expect(toolResult['content'][1]['source']['media_type'], 'image/png');
      expect(toolResult['content'][1]['source']['data'], 'QUJD');
    });

    test('a model that never stops hits the turn limit', () async {
      final mcp = FakeMcp(tools: [_tool('get_app_summary')]);
      final api = FakeApi([
        for (var i = 0; i < 4; i++) _toolUseReply('get_app_summary', {}),
      ]);
      await api.start();
      addTearDown(api.stop);
      addTearDown(mcp.dispose);

      final run = await _runner(api, maxTurns: 2).run(_task(), mcp);

      expect(run.hitTurnLimit, isTrue);
      expect(run.turns, 2);
      expect(api.received, hasLength(2));
    });

    test('429 is retried, then succeeds', () async {
      final mcp = FakeMcp(tools: [_tool('get_app_summary')]);
      final api = FakeApi([429, _textReply('ANSWER: 42')]);
      await api.start();
      addTearDown(api.stop);
      addTearDown(mcp.dispose);

      final run = await _runner(api).run(_task(), mcp);

      expect(run.error, isNull);
      expect(run.answer, '42');
      expect(api.received, hasLength(2));
    });

    test('the next turn sees a refreshed tool list', () async {
      final mcp = FakeMcp(tools: [_tool('get_app_summary')]);
      final api = FakeApi([
        _toolUseReply('get_app_summary', {}),
        _textReply('ANSWER: 42'),
      ]);
      await api.start();
      addTearDown(api.stop);
      addTearDown(mcp.dispose);

      final run = _runner(api).run(_task(), mcp);
      mcp.pushTools([_tool('get_app_summary'), _tool('get_riverpod_state')]);
      await run;

      final secondTools = api.received[1]['tools'] as List;
      expect(secondTools.map((t) => t['name']), contains('get_riverpod_state'));
    });

    test('cache usage fields are summed across turns', () async {
      final mcp = FakeMcp(tools: [_tool('get_app_summary')]);
      final api = FakeApi([
        _usage(_toolUseReply('get_app_summary', {}), {
          'cache_creation_input_tokens': 400,
          'cache_read_input_tokens': 0,
        }),
        _usage(_textReply('ANSWER: 42'), {
          'cache_creation_input_tokens': 0,
          'cache_read_input_tokens': 900,
        }),
      ]);
      await api.start();
      addTearDown(api.stop);
      addTearDown(mcp.dispose);

      final run = await _runner(api).run(_task(), mcp);

      expect(run.cacheWriteTokens, 400);
      expect(run.cacheReadTokens, 900);
    });

    test('a huge tool result is truncated before the model sees it', () async {
      final mcp = FakeMcp(tools: [_tool('get_app_summary')]);
      mcp.onCall = (_) => McpCallResult(
        [
          {'type': 'text', 'text': 'x' * 5000},
        ],
        false,
        1,
        5000,
      );
      final api = FakeApi([
        _toolUseReply('get_app_summary', {}),
        _textReply('ANSWER: 42'),
      ]);
      await api.start();
      addTearDown(api.stop);
      addTearDown(mcp.dispose);

      await AnthropicRunner(
        apiKey: _sentinelKey,
        model: 'test-model',
        baseUrl: 'http://127.0.0.1:${api.port}',
        maxToolResultChars: 100,
      ).run(_task(), mcp);

      final toolResult =
          ((api.received[1]['messages'] as List).last['content'] as List).first;
      final text = toolResult['content'][0]['text'] as String;
      expect(text.length, lessThan(200));
      expect(text, contains('truncated'));
    });

    test('the call cap stops a chatty model', () async {
      final mcp = FakeMcp(tools: [_tool('get_app_summary')]);
      final api = FakeApi([
        for (var i = 0; i < 5; i++) _toolUseReply('get_app_summary', {}),
      ]);
      await api.start();
      addTearDown(api.stop);
      addTearDown(mcp.dispose);

      final run = await AnthropicRunner(
        apiKey: _sentinelKey,
        model: 'test-model',
        baseUrl: 'http://127.0.0.1:${api.port}',
        maxCalls: 2,
      ).run(_task(), mcp);

      expect(run.hitCallLimit, isTrue);
      expect(run.calls, hasLength(2));
      expect(runPassed(_task(), run), isFalse);
    });
  });

  group('reporting', () {
    test('summarize takes medians and counts passes', () {
      final task = _task(id: 'shop_count');
      final report = summarize(
        model: 'test-model',
        device: 'windows',
        serverCommit: 'abc1234',
        apps: {
          'fp_lab_shop': AppInfo(
            commit: 'def5678',
            toolsListed: 51,
            toolListChars: 33000,
            toolListUtf8Bytes: 33000,
          ),
        },
        results: [
          TaskRun(task: task, run: _run(calls: 1, input: 100), passed: true),
          TaskRun(task: task, run: _run(calls: 3, input: 300), passed: true),
          TaskRun(task: task, run: _run(calls: 2, input: 200), passed: false),
        ],
        identity: _identity(),
      );

      final summary = report.tasks['shop_count']!;
      expect(summary.passed, 2);
      expect(summary.failed, 1);
      expect(summary.runs, 3);
      expect(summary.executed, 3);
      expect(summary.callsMedian, 2);
      expect(summary.inputTokensMedian, 200);
      expect(report.totals.passRate, closeTo(2 / 3, 1e-9));
      // The empty pricing table prices nothing: no invented cost.
      expect(report.totals.costKnown, isFalse);
      expect(report.totals.benchmarkValid, isTrue);
      expect(report.schemaVersion, reportSchemaVersion);
      expect(report.identity, isNotNull);
      expect(report.legacy, isFalse);
    });

    test('an explicit price yields a known cost; unknown is not invented', () {
      final task = _task(id: 'shop_count');
      RunReport build(String model) => summarize(
        model: model,
        device: 'windows',
        serverCommit: 'abc1234',
        apps: const {},
        identity: _identity(model: model),
        pricing: _priced,
        results: [
          TaskRun(
            task: task,
            run: _run(input: 1000000, output: 1000000),
            passed: true,
          ),
        ],
      );

      final priced = build('test-model');
      expect(priced.totals.costKnown, isTrue);
      expect(priced.totals.costUsd, closeTo(3 + 15, 1e-9));

      final mystery = build('a-model-nobody-priced');
      expect(mystery.totals.costKnown, isFalse);
      expect(mystery.totals.costUsd, 0);
    });

    test('compare reports a drop and refuses a changed app commit', () {
      final task = _task(id: 'shop_count');
      RunReport build(int pass, String appCommit) => summarize(
        model: 'test-model',
        device: 'windows',
        serverCommit: 'abc1234',
        apps: {
          'fp_lab_shop': AppInfo(
            commit: appCommit,
            toolsListed: 51,
            toolListChars: 33000,
            toolListUtf8Bytes: 33000,
          ),
        },
        results: [
          for (var i = 0; i < 3; i++)
            TaskRun(task: task, run: _run(), passed: i < pass),
        ],
        identity: _identity(),
      );

      final baseline = build(3, 'def5678');
      final dropped = compareReports(baseline, build(2, 'def5678'));
      expect(dropped.regressed, isTrue);
      expect(dropped.lines.join('\n'), contains('shop_count: 3/3 → 2/3'));

      expect(
        () => compareReports(baseline, build(3, 'different')),
        throwsA(isA<CompareRefused>()),
      );
    });
  });

  group('versioned outcomes', () {
    test('outcomes are counted apart and exclude non-executions', () {
      final task = _task(id: 't');
      final report = summarize(
        model: 'test-model',
        device: 'windows',
        serverCommit: 'abc1234',
        apps: const {},
        identity: _identity(),
        results: [
          TaskRun(task: task, run: _run(), passed: true),
          TaskRun(
            task: task,
            run: _run(text: 'ANSWER: wrong'),
            passed: false,
          ),
          TaskRun(task: task, run: _run(error: true), passed: false),
          TaskRun.skipped(task, 'unsupported here'),
          TaskRun.budget(task, 'spend guard reached'),
        ],
      );

      final summary = report.tasks['t']!;
      expect(summary.passed, 1);
      expect(summary.failed, 1);
      expect(summary.errors, 1);
      expect(summary.skipped, 1);
      expect(summary.budgetExhausted, 1);
      expect(summary.runs, 5);
      expect(summary.executed, 2);
      expect(summary.reasons, contains('unsupported here'));
      // Pass rate is over executed cases, so the error and skip do not move it.
      expect(report.totals.passRate, closeTo(0.5, 1e-9));
      // An infrastructure error blocks benchmark acceptance.
      expect(report.totals.benchmarkValid, isFalse);
    });

    test('only skips is not a benchmark; failed answers are', () {
      final task = _task(id: 't');
      RunReport build(List<TaskRun> results) => summarize(
        model: 'test-model',
        device: 'windows',
        serverCommit: 'abc1234',
        apps: const {},
        identity: _identity(),
        results: results,
      );

      final skipped = build([TaskRun.skipped(task, 'no fixture')]);
      expect(skipped.totals.executed, 0);
      expect(skipped.totals.passRate, 0);
      expect(skipped.totals.benchmarkValid, isFalse);

      final wrong = build([
        TaskRun(
          task: task,
          run: _run(text: 'ANSWER: nope'),
          passed: false,
        ),
      ]);
      expect(wrong.totals.passRate, 0);
      expect(wrong.totals.benchmarkValid, isTrue);
    });
  });

  group('explicit pricing', () {
    test('a known price is computed from all four token kinds', () {
      final cost = estimateCost('test-model', [
        _run(input: 1000000, output: 1000000),
      ], _priced);
      expect(cost.known, isTrue);
      expect(cost.usd, closeTo(3 + 15, 1e-9));
    });

    test('an unpriced model is unknown, never a fallback', () {
      final cost = estimateCost('mystery', [_run()], _priced);
      expect(cost.known, isFalse);
      expect(cost.usd, 0);
      expect(_priced.priceFor('mystery'), isNull);
    });

    test('a malformed price is rejected, not read as unknown', () {
      expect(
        () => PricingConfig.parse(
          '{"version":1,"models":{"m":{"input":-1,"output":1,'
          '"cacheRead":1,"cacheWrite":1}}}',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PricingConfig.parse('{"models":{}}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('the committed table parses', () {
      final config = PricingConfig.load(File('tool/eval/pricing.json'));
      expect(config.version, greaterThanOrEqualTo(1));
      expect(config.versionTag, startsWith('v'));
    });
  });

  group('policy wrapper', () {
    test('refuses a destructive tool and allows a read', () async {
      final inner = FakeMcp(tools: [_tool('get_app_summary')]);
      addTearDown(inner.dispose);
      final policy = PolicyClient(inner);

      final refused = await policy.call('set_shared_preference', {
        'key': 'x',
        'value': 'y',
      });
      expect(refused.isError, isTrue);
      expect(refused.text, contains('Refused'));
      expect(inner.called, isEmpty, reason: 'the inner client is never called');

      final allowed = await policy.call('get_app_summary');
      expect(allowed.isError, isFalse);
      expect(inner.called, ['get_app_summary']);
    });

    test('the deny set is exactly the server\'s destructive tools', () {
      expect(
        destructiveToolNames,
        containsAll([
          'scenario',
          'call_custom_tool',
          'supabase_session',
          'set_secure_storage_key',
          'set_shared_preference',
        ]),
      );
      expect(destructiveToolNames, isNot(contains('get_app_summary')));
      expect(destructiveToolNames, isNot(contains('set_app_settings')));
    });

    test('refuses a destructive tool named by a nested chain step', () async {
      final inner = FakeMcp(tools: [_tool('execute_action_chain')]);
      addTearDown(inner.dispose);
      final policy = PolicyClient(inner);

      final refused = await policy.call('execute_action_chain', {
        'steps': [
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'a'},
          },
          {
            'tool': 'scenario',
            'arguments': {'load': 'x'},
          },
        ],
      });
      expect(refused.isError, isTrue);
      expect(refused.text, contains('scenario'));
      expect(inner.called, isEmpty);

      final allowed = await policy.call('execute_action_chain', {
        'steps': [
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'a'},
          },
        ],
      });
      expect(allowed.isError, isFalse);
      expect(inner.called, ['execute_action_chain']);
    });
  });

  group('identity and comparison', () {
    RunReport report({
      required List<TaskRun> results,
      RunIdentity? identity,
      Map<String, AppInfo> apps = const {},
    }) => summarize(
      model: 'test-model',
      device: 'windows',
      serverCommit: 'abc1234',
      apps: apps,
      results: results,
      identity: identity ?? _identity(),
    );

    test('a legacy summary is incomparable', () {
      final legacy = RunReport.fromJson(
        jsonDecode(
              jsonEncode({
                'model': 'test-model',
                'device': 'windows',
                'server_commit': 'abc1234',
                'apps': <String, Object?>{},
                'tasks': {
                  'shop_count': {
                    'pass': 3,
                    'runs': 3,
                    'calls_median': 1,
                    'error_calls_median': 0,
                    'input_tokens_median': 10,
                    'output_tokens_median': 5,
                    'cache_read_tokens_median': 0,
                    'seconds_median': 1,
                    'tools_used': <String, int>{},
                  },
                },
                'totals': {
                  'pass': 3,
                  'runs': 3,
                  'pass_rate': 1.0,
                  'calls_median_sum': 1,
                  'input_tokens_median_sum': 10,
                  'cost_usd': 0.01,
                },
              }),
            )
            as Map<String, dynamic>,
      );

      expect(legacy.legacy, isTrue);
      expect(legacy.schemaVersion, 1);
      final current = report(
        results: [
          TaskRun(
            task: _task(id: 'shop_count'),
            run: _run(),
            passed: true,
          ),
        ],
      );
      expect(
        () => compareReports(legacy, current),
        throwsA(isA<CompareRefused>()),
      );
    });

    test('a different model is refused', () {
      final baseline = report(
        results: [
          TaskRun(
            task: _task(id: 'shop_count'),
            run: _run(),
            passed: true,
          ),
        ],
      );
      final other = report(
        results: [
          TaskRun(
            task: _task(id: 'shop_count'),
            run: _run(),
            passed: true,
          ),
        ],
        identity: _identity(model: 'another-model'),
      );
      expect(
        () => compareReports(baseline, other),
        throwsA(isA<CompareRefused>()),
      );
    });

    test('a missing task makes the comparison incomplete, not passing', () {
      final baseline = report(
        results: [
          TaskRun(
            task: _task(id: 'a'),
            run: _run(),
            passed: true,
          ),
          TaskRun(
            task: _task(id: 'b'),
            run: _run(),
            passed: true,
          ),
        ],
      );
      final current = report(
        results: [
          TaskRun(
            task: _task(id: 'a'),
            run: _run(),
            passed: true,
          ),
        ],
      );
      final comparison = compareReports(baseline, current);
      expect(comparison.incomplete, isTrue);
      expect(comparison.lines.join('\n'), contains('b: missing'));
    });

    test('an infrastructure error makes the comparison incomplete', () {
      final baseline = report(
        results: [
          TaskRun(
            task: _task(id: 'a'),
            run: _run(),
            passed: true,
          ),
        ],
      );
      final current = report(
        results: [
          TaskRun(
            task: _task(id: 'a'),
            run: _run(error: true),
            passed: false,
          ),
        ],
      );
      final comparison = compareReports(baseline, current);
      expect(comparison.incomplete, isTrue);
      expect(comparison.regressed, isFalse);
    });
  });

  group('mcp adapter (real subprocess)', () {
    Future<McpSession> startFake([Map<String, String> env = const {}]) =>
        McpSession.start(
          entrypoint: 'test/fixtures/fake_mcp_server.dart',
          serverArgs: const [],
          workingDirectory: Directory.current.path,
          environment: env,
        );

    test('keeps the negotiated protocol, server identity and structured '
        'content', () async {
      final session = await startFake({
        'FAKE_PROTOCOL_VERSION': '2025-11-25',
        'FAKE_TOOL_COUNT': '2',
        'FAKE_STRUCTURED': '1',
      });
      addTearDown(session.close);

      expect(session.negotiatedProtocol, '2025-11-25');
      expect(session.tools, hasLength(2));
      expect(session.serverInfo['name'], 'fake-mcp-server');

      final result = await session.call('fake_tool_0');
      expect(result.isError, isFalse);
      expect(result.structured?['route'], '/home');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a banner on stdout fails the session', () async {
      await expectLater(
        startFake({'FAKE_BANNER': r'this is not json\n'}),
        throwsA(isA<McpException>()),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a pending request is rejected when the server exits', () async {
      await expectLater(
        startFake({'FAKE_EXIT_ON_METHOD': 'tools/list'}),
        throwsA(isA<McpException>()),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  test('the key never appears in anything the run writes', () async {
    final mcp = FakeMcp(tools: [_tool('get_app_summary')]);
    final api = FakeApi([
      _toolUseReply('get_app_summary', {}),
      _textReply('ANSWER: 42'),
    ]);
    await api.start();
    addTearDown(api.stop);
    addTearDown(mcp.dispose);

    final run = await _runner(api).run(_task(), mcp);
    final report = summarize(
      model: 'test-model',
      device: 'windows',
      serverCommit: 'abc1234',
      apps: const {},
      results: [TaskRun(task: _task(), run: run, passed: true)],
      identity: _identity(),
    );
    final written =
        jsonEncode(run.toJson()) +
        runReportToJson(report) +
        api.received.toString();

    expect(written, isNot(contains('SENTINEL')));
    expect(written, isNot(contains(_sentinelKey)));
  });

  group('the committed task set', () {
    // Only a paid run reads tasks.yaml otherwise, so validate it first: a
    // duplicate id, an empty prompt or answer, an unknown app or match mode
    // should fail here, before the maintainer spends money (task 01 §5).
    final tasks = loadTasks('tool/eval/tasks.yaml');

    test('has the 14 tasks from the spec, each well formed', () {
      expect(tasks, hasLength(14));
      expect(tasks.map((t) => t.id).toSet(), hasLength(tasks.length));
      for (final task in tasks) {
        expect(task.id, isNotEmpty);
        expect(task.prompt, isNotEmpty, reason: task.id);
        expect(task.answer, isNotEmpty, reason: task.id);
        expect(task.prompt, isNot(contains('ANSWER:')), reason: task.id);
        expect(defaultScenarios, contains(task.app), reason: task.id);
      }
    });

    test('covers both lab apps', () {
      expect(tasks.map((t) => t.app).toSet(), {'fp_lab_shop', 'fp_lab_notes'});
    });
  });
}

AgentRun _run({
  int calls = 1,
  int input = 100,
  int output = 10,
  String text = 'ANSWER: 42',
  bool error = false,
  bool turnLimit = false,
}) => AgentRun(
  calls: [for (var i = 0; i < calls; i++) ToolCallRecord('t$i', 1, false, 1)],
  turns: 1,
  inputTokens: input,
  outputTokens: output,
  cacheWriteTokens: 0,
  cacheReadTokens: 0,
  seconds: 1.5,
  finalText: text,
  hitTurnLimit: turnLimit,
  error: error ? 'boom' : null,
);
