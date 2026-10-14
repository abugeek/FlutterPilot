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
import '../tool/eval/src/mcp_session.dart';
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
            toolListBytes: 33000,
          ),
        },
        results: [
          TaskRun(task: task, run: _run(calls: 1, input: 100), passed: true),
          TaskRun(task: task, run: _run(calls: 3, input: 300), passed: true),
          TaskRun(task: task, run: _run(calls: 2, input: 200), passed: false),
        ],
      );

      final summary = report.tasks['shop_count']!;
      expect(summary.pass, 2);
      expect(summary.runs, 3);
      expect(summary.callsMedian, 2);
      expect(summary.inputTokensMedian, 200);
      expect(report.totals.passRate, closeTo(2 / 3, 1e-9));
      expect(report.totals.costUsd, greaterThan(0));
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
            toolListBytes: 33000,
          ),
        },
        results: [
          for (var i = 0; i < 3; i++)
            TaskRun(task: task, run: _run(), passed: i < pass),
        ],
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
