// The Messages API agent loop (task 01 §2): send, run the tools the model asked
// for through the MCP session, send the results back, until it stops or hits
// the turn limit. No SDK dependency; dart:io HttpClient only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'agent.dart';
import 'mcp_session.dart';
import 'tasks.dart';

class AnthropicRunner implements AgentRunner {
  AnthropicRunner({
    required this.apiKey,
    required this.model,
    this.maxTurns = 40,
    this.maxCalls = 0,
    this.maxTokens = 4096,
    this.baseUrl = 'https://api.anthropic.com',
    this.requestTimeout = const Duration(minutes: 2),
    this.maxRunSeconds = 0,
    this.maxToolResultChars = 100000,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final String apiKey;

  @override
  final String model;
  final int maxTurns;
  final int maxTokens;

  /// A hard cap on tool calls per run; 0 leaves only the turn cap.
  final int maxCalls;

  /// Overridable so tests can point at a local fake (README).
  final String baseUrl;

  /// One Messages API request must answer within this window (task 04 §9).
  final Duration requestTimeout;

  /// A whole run stops after this many seconds; 0 disables the run deadline.
  final int maxRunSeconds;

  /// The largest tool result forwarded to the model, in characters.
  final int maxToolResultChars;
  final HttpClient _client;

  /// The one instruction added to the server's own; we are measuring
  /// FlutterPilot's guidance, not our own.
  static const _guidance =
      'You can only act through these tools. When you are finished, write '
      'your final answer on the last line as `ANSWER: <value>`.';

  @override
  Future<AgentRun> run(EvalTask task, McpClient session) async {
    final calls = <ToolCallRecord>[];
    var turns = 0;
    var inputTokens = 0;
    var outputTokens = 0;
    var cacheWriteTokens = 0;
    var cacheReadTokens = 0;
    var finalText = '';
    var hitTurnLimit = false;
    var hitCallLimit = false;
    final stopwatch = Stopwatch()..start();

    final system = <Map<String, dynamic>>[
      if (session.instructions.isNotEmpty)
        {
          'type': 'text',
          'text': session.instructions,
          // One cache breakpoint on the system block, one on the last tool:
          // both are identical across turns and tasks (task 01 §2).
          'cache_control': {'type': 'ephemeral'},
        },
      {'type': 'text', 'text': _guidance},
    ];
    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': task.prompt},
    ];

    String? error;
    try {
      while (true) {
        final elapsed = stopwatch.elapsed.inSeconds;
        if (maxRunSeconds > 0 && elapsed >= maxRunSeconds) {
          error =
              'run deadline exceeded after ${elapsed}s '
              '(--max-run-seconds $maxRunSeconds)';
          break;
        }
        turns++;
        final response = await _send({
          'model': model,
          'max_tokens': maxTokens,
          'system': system,
          'tools': _toolsFor(session.tools),
          'messages': messages,
        });
        final usage =
            (response['usage'] as Map?)?.cast<String, dynamic>() ?? const {};
        inputTokens += _int(usage['input_tokens']);
        outputTokens += _int(usage['output_tokens']);
        cacheWriteTokens += _int(usage['cache_creation_input_tokens']);
        cacheReadTokens += _int(usage['cache_read_input_tokens']);

        final content = [
          for (final block in (response['content'] as List? ?? const []))
            (block as Map).cast<String, dynamic>(),
        ];
        messages.add({'role': 'assistant', 'content': content});
        for (final block in content) {
          if (block['type'] == 'text') finalText = '${block['text']}';
        }

        if (response['stop_reason'] != 'tool_use') break;
        if (turns >= maxTurns) {
          hitTurnLimit = true;
          break;
        }

        final results = <Map<String, dynamic>>[];
        for (final block in content.where((b) => b['type'] == 'tool_use')) {
          final name = '${block['name']}';
          final arguments =
              (block['input'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final result = await session.call(name, arguments);
          calls.add(
            ToolCallRecord(
              name,
              result.milliseconds,
              result.isError,
              result.chars,
            ),
          );
          results.add({
            'type': 'tool_result',
            'tool_use_id': '${block['id']}',
            'content': _toolResultContent(result),
            if (result.isError) 'is_error': true,
          });
        }
        messages.add({'role': 'user', 'content': results});
        if (maxCalls > 0 && calls.length >= maxCalls) {
          hitCallLimit = true;
          break;
        }
      }
    } catch (e) {
      error = '$e';
    }
    stopwatch.stop();
    return AgentRun(
      calls: calls,
      turns: turns,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cacheWriteTokens: cacheWriteTokens,
      cacheReadTokens: cacheReadTokens,
      seconds: stopwatch.elapsedMilliseconds / 1000,
      finalText: finalText,
      hitTurnLimit: hitTurnLimit,
      hitCallLimit: hitCallLimit,
      error: error,
    );
  }

  List<Map<String, dynamic>> _toolsFor(List<McpTool> tools) => [
    for (var i = 0; i < tools.length; i++)
      {
        'name': tools[i].name,
        'description': tools[i].description,
        'input_schema': tools[i].inputSchema,
        if (i == tools.length - 1) 'cache_control': {'type': 'ephemeral'},
      },
  ];

  /// MCP content as Messages API blocks: text stays text, images become image
  /// blocks (screenshots matter to these tasks), and an empty result still
  /// carries one text block because the API rejects empty content. The total
  /// text is bounded by [maxToolResultChars] (task 04 §9).
  List<Map<String, dynamic>> _toolResultContent(McpCallResult result) {
    var remaining = maxToolResultChars;
    final blocks = <Map<String, dynamic>>[];
    for (final block in result.content) {
      if (block['type'] == 'image') {
        blocks.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': '${block['mimeType'] ?? 'image/png'}',
            'data': '${block['data']}',
          },
        });
        continue;
      }
      final text = '${block['text'] ?? ''}';
      if (remaining <= 0) {
        blocks.add({'type': 'text', 'text': '…[result truncated]'});
        break;
      }
      if (text.length <= remaining) {
        blocks.add({'type': 'text', 'text': text});
        remaining -= text.length;
      } else {
        blocks.add({
          'type': 'text',
          'text':
              '${text.substring(0, remaining)}\n…[truncated '
              '${text.length - remaining} chars]',
        });
        remaining = 0;
      }
    }
    return blocks.isEmpty
        ? [
            {'type': 'text', 'text': '(no output)'},
          ]
        : blocks;
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> body) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final request = await _client.postUrl(Uri.parse('$baseUrl/v1/messages'));
      request.headers
        ..set('content-type', 'application/json')
        ..set('anthropic-version', '2023-06-01')
        // The key lives only here, in the request header.
        ..set('x-api-key', apiKey);
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(requestTimeout);
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        return jsonDecode(text) as Map<String, dynamic>;
      }
      final retryable =
          response.statusCode == 429 || response.statusCode >= 500;
      if (!retryable || attempt >= 5) {
        throw HttpException(
          'Messages API ${response.statusCode}: ${_short(text)}',
        );
      }
      await Future<void>.delayed(Duration(seconds: 1 << attempt));
    }
  }

  int _int(Object? value) => value is num ? value.toInt() : 0;

  String _short(String text) =>
      text.length <= 500 ? text : '${text.substring(0, 500)}…';
}
