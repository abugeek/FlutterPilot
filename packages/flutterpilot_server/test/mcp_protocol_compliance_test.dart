/// Task 19 · headless MCP protocol compliance, over real stdio.
///
/// Every test starts `flutterpilot_server` the way an MCP client does — `dart
/// run bin/flutterpilot_server.dart` with JSON-RPC on stdin/stdout — performs
/// the `initialize` / `notifications/initialized` handshake itself, and then
/// drives one matrix of the protocol. Nothing here needs a running Flutter
/// app: discovery finds none, and every assertion is about framing, declared
/// schemas and refusals rather than app state.
///
/// The client negotiates `2025-11-25`, the newest classic-`initialize` version
/// mcp_dart supports (the `2026-07-28` profile is stateless and skips
/// `initialize`). That choice is visible in Matrix 4: with a modern version the
/// SDK reports a schema violation as `CallToolResult(isError: true)`, the shape
/// a client is expected to read, instead of a `-32602` JSON-RPC error.
@Timeout(Duration(seconds: 120))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late _Inspector inspector;

  setUp(() async {
    inspector = await _Inspector.start();
    await inspector.initialize();
  });

  tearDown(() => inspector.kill());

  group('Matrix 1 · handshake & capability exchange', () {
    test('negotiates the version and identifies itself as FlutterPilot', () {
      final result = inspector.initializeResult;
      expect(result['protocolVersion'], '2025-11-25');
      final serverInfo = result['serverInfo'] as Map<String, dynamic>;
      expect(serverInfo['name'], 'FlutterPilot');
      expect(serverInfo['version'], isNotEmpty);
      expect(result['instructions'], isNotEmpty);
    });

    test('declares the tools, resources and prompts capabilities', () {
      final capabilities =
          inspector.initializeResult['capabilities'] as Map<String, dynamic>;
      final tools = capabilities['tools'] as Map<String, dynamic>?;
      expect(tools?['listChanged'], isTrue);
      final resources = capabilities['resources'] as Map<String, dynamic>?;
      expect(resources?['listChanged'], isTrue);
      expect(resources?['subscribe'], isTrue);
      final prompts = capabilities['prompts'];
      expect(prompts, isA<Map<String, dynamic>>());
      expect(
        (prompts as Map<String, dynamic>)['listChanged'],
        isNot(true),
        reason: 'prompts are static, so prompts/list_changed is never sent',
      );
    });

    test('serves requests after notifications/initialized', () async {
      // initialize() already proved this by calling tools/list after the
      // notification; one more round trip pins it down.
      final tools = await inspector.tools();
      expect(tools, isNotEmpty);
    });
  });

  group('Matrix 2 · schema discovery audit', () {
    test('every tool has a snake_case name, a description and an object '
        'inputSchema', () async {
      final tools = await inspector.tools();
      expect(tools, isNotEmpty);
      final problems = <String>[];
      for (final tool in tools) {
        final name = tool['name']?.toString() ?? '';
        if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
          problems.add('tool "$name" is not snake_case');
        }
        if ((tool['description']?.toString().trim() ?? '').isEmpty) {
          problems.add('tool "$name" has no description');
        }
        final schema = tool['inputSchema'];
        if (schema is! Map || schema['type'] != 'object') {
          problems.add('tool "$name" inputSchema is not {type: object}');
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('every tool carries the four standard annotations', () async {
      final tools = await inspector.tools();
      const hints = [
        'readOnlyHint',
        'destructiveHint',
        'idempotentHint',
        'openWorldHint',
      ];
      final problems = <String>[];
      for (final tool in tools) {
        final name = tool['name'];
        final annotations = tool['annotations'];
        if (annotations is! Map) {
          problems.add('tool "$name" has no annotations');
          continue;
        }
        for (final hint in hints) {
          if (annotations[hint] is! bool) {
            problems.add('tool "$name" is missing boolean $hint');
          }
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('resources/list offers the five flutterpilot resources', () async {
      final response = await inspector.request('resources/list');
      expect(response['error'], isNull, reason: '$response');
      final resources = (response['result'] as Map)['resources'] as List;
      expect(resources, hasLength(5));
      final uris = [
        for (final resource in resources) (resource as Map)['uri'].toString(),
      ];
      expect(
        uris,
        containsAll(<String>[
          'flutterpilot://app/summary',
          'flutterpilot://app/errors',
          'flutterpilot://app/widget-tree',
          'flutterpilot://app/logs',
          'flutterpilot://devices',
        ]),
      );
      for (final resource in resources) {
        expect(resource['name']?.toString(), isNotEmpty, reason: '$resource');
        expect(
          resource['description']?.toString(),
          isNotEmpty,
          reason: '$resource',
        );
        expect(
          resource['mimeType']?.toString(),
          isNotEmpty,
          reason: '$resource',
        );
      }
    });

    test(
      'resources/templates/list offers widget and route templates',
      () async {
        final response = await inspector.request('resources/templates/list');
        expect(response['error'], isNull, reason: '$response');
        final templates =
            (response['result'] as Map)['resourceTemplates'] as List;
        expect(templates, hasLength(greaterThanOrEqualTo(2)));
        final byUri = <String, Map>{
          for (final template in templates)
            (template as Map)['uriTemplate'].toString(): template,
        };
        expect(byUri.keys, contains('flutterpilot://app/widgets/{key}'));
        expect(byUri.keys, contains('flutterpilot://app/routes/{path}'));
        for (final template in templates) {
          expect(template['name']?.toString(), isNotEmpty, reason: '$template');
          expect(
            template['description']?.toString(),
            isNotEmpty,
            reason: '$template',
          );
          expect(template['mimeType'], 'application/json', reason: '$template');
        }
        expect(
          byUri['flutterpilot://app/widgets/{key}']!['name'],
          'widget_by_key',
        );
        expect(
          byUri['flutterpilot://app/routes/{path}']!['name'],
          'route_by_path',
        );
      },
    );

    test('prompts/list offers the guide plus four workflow prompts', () async {
      final response = await inspector.request('prompts/list');
      expect(response['error'], isNull, reason: '$response');
      final prompts = (response['result'] as Map)['prompts'] as List;
      expect(prompts, hasLength(5));
      final byName = <String, Map>{
        for (final prompt in prompts)
          (prompt as Map)['name'].toString(): prompt,
      };
      expect(
        byName.keys,
        containsAll(<String>[
          'flutterpilot_guide',
          'debug_layout_overflow',
          'diagnose_exception',
          'create_integration_test',
          'audit_screen_health',
        ]),
      );
      for (final prompt in prompts) {
        expect(
          prompt['description']?.toString(),
          isNotEmpty,
          reason: '$prompt',
        );
      }
      // The four workflows each declare their optional argument.
      expect(_argumentNames(byName['debug_layout_overflow']!), ['widgetKey']);
      expect(_argumentNames(byName['diagnose_exception']!), ['errorIndex']);
      expect(_argumentNames(byName['create_integration_test']!), ['name']);
      expect(_argumentNames(byName['audit_screen_health']!), ['route']);
      // The guide takes no arguments.
      expect(_argumentNames(byName['flutterpilot_guide']!), isEmpty);
    });
  });

  group('Matrix 3 · standard JSON-RPC errors', () {
    test('an unknown method is -32601 Method not found', () async {
      final response = await inspector.request('flutterpilot/does_not_exist');
      final error = response['error'] as Map<String, dynamic>?;
      expect(error, isNotNull, reason: '$response');
      expect(error!['code'], -32601);
      expect(error['message'], contains('not found'));
    });

    test('malformed JSON on stdin is -32700 Parse error', () async {
      inspector.sendRaw('{ this is not json');
      final message = await inspector.waitForMessage(
        (response) => (response['error'] as Map?)?['code'] == -32700,
      );
      expect((message['error'] as Map)['message'], 'Parse error');
      // A framing error must not take the connection down.
      final after = await inspector.request('tools/list');
      expect(after['error'], isNull, reason: '$after');
    });

    test('a structurally invalid request is -32600 Invalid Request', () async {
      // No "method" member at all.
      inspector.sendRaw(jsonEncode({'jsonrpc': '2.0', 'id': 8001}));
      final message = await inspector.waitForMessage(
        (response) => response['id'] == 8001,
      );
      final error = message['error'] as Map;
      expect(error['code'], -32600);
      expect(error['message'], 'Invalid Request');
      final after = await inspector.request('tools/list');
      expect(after['error'], isNull, reason: '$after');
    });
  });

  group('Matrix 4 · argument serialization & self-correction', () {
    test('a well-typed call executes', () async {
      final response = await inspector.request('tools/call', {
        'name': 'get_debug_logs',
        'arguments': {'sinceSeconds': 120, 'limit': 5},
      });
      expect(response['error'], isNull, reason: '$response');
      final result = response['result'] as Map<String, dynamic>;
      expect(result['isError'], isNot(true), reason: '$result');
      expect(_textOf(result), isNotEmpty);
    });

    test('a stringified number and boolean are refused by name, never with a '
        'retry hint', () async {
      // mcp_dart validates a tools/call against the declared inputSchema before
      // FlutterPilot's own coercion runs, so a "100"/"true" that a sloppy client
      // stringified is refused by the protocol layer. The point of this test is
      // that the refusal is precise and actionable — the argument is named and
      // the generic "the app was busy, retry" wrapper is never reached. (The
      // coercion layer itself is covered by tool_argument_fuzz_test.dart, which
      // exercises the nested-call path where no transport validates first.)
      final number = _refusalMessage(
        await inspector.request('tools/call', {
          'name': 'get_debug_logs',
          'arguments': {'sinceSeconds': '100'},
        }),
      );
      expect(number, contains('sinceSeconds'), reason: number);
      _expectNoRetryHint(number);

      final boolean = _refusalMessage(
        await inspector.request('tools/call', {
          'name': 'get_errors',
          'arguments': {'report': 'true'},
        }),
      );
      expect(boolean, contains('report'), reason: boolean);
      _expectNoRetryHint(boolean);
    });

    test(
      'an unknown extra argument is refused with isError naming it',
      () async {
        final response = await inspector.request('tools/call', {
          'name': 'get_debug_logs',
          'arguments': {'level': 'error', '__not_a_real_option__': 1},
        });
        expect(response['error'], isNull, reason: '$response');
        final result = response['result'] as Map<String, dynamic>;
        expect(result['isError'], isTrue, reason: '$result');
        final text = _textOf(result);
        expect(text, contains('__not_a_real_option__'), reason: text);
        _expectNoRetryHint(text);
      },
    );

    test(
      'a missing required argument is refused with isError naming it',
      () async {
        final response = await inspector.request('tools/call', {
          'name': 'execute_action_chain',
          'arguments': <String, dynamic>{},
        });
        final message = _refusalMessage(response);
        expect(message, contains('steps'), reason: message);
        _expectNoRetryHint(message);
      },
    );

    test(
      'resources/read with a templated URI dispatches to its handler',
      () async {
        // Neither template needs a running app: with none connected they answer
        // with the same "no app" body the fixed resources use.
        for (final uri in [
          'flutterpilot://app/widgets/test_key',
          'flutterpilot://app/routes/current',
        ]) {
          final response = await inspector.request('resources/read', {
            'uri': uri,
          });
          expect(response['error'], isNull, reason: '$response');
          final contents = (response['result'] as Map)['contents'] as List;
          expect(contents, isNotEmpty, reason: uri);
          final text = (contents.first as Map)['text'] as String;
          expect(
            text,
            contains('No Flutter app currently connected'),
            reason: uri,
          );
        }
      },
    );
  });
}

/// The names `prompts/list` advertises for [prompt], in order.
List<String> _argumentNames(Map prompt) {
  final arguments = prompt['arguments'];
  if (arguments is! List) return const [];
  return [
    for (final argument in arguments)
      if (argument is Map) '${argument['name']}',
  ];
}

/// The human-readable message of a tool refusal.
///
/// A refusal is either a `CallToolResult(isError: true)` (the modern shape a
/// client reads) or a `-32602 Invalid arguments` JSON-RPC error. Both are
/// standards-compliant and which one appears depends on the negotiated
/// protocol version, so the suite accepts either and checks the message.
String _refusalMessage(Map<String, dynamic> response) {
  final error = response['error'];
  if (error is Map) return '${error['message']}';
  final result = response['result'];
  expect(
    result,
    isA<Map<String, dynamic>>(),
    reason: 'not a refusal: $response',
  );
  final map = result as Map<String, dynamic>;
  expect(map['isError'], isTrue, reason: 'not a refusal: $response');
  return _textOf(map);
}

/// Asserts a refusal never falls back to the old generic wrapper an agent reads
/// as "the app is busy, retry" (task 02 §D) — a refusal must say what was
/// wrong, not invite a blind retry of the same broken call.
void _expectNoRetryHint(String message) {
  final lower = message.toLowerCase();
  expect(lower, isNot(contains('retry')), reason: message);
  expect(lower, isNot(contains('busy')), reason: message);
}

/// The concatenated text parts of a `CallToolResult`.
String _textOf(Map<String, dynamic> result) {
  final content = result['content'];
  if (content is! List) return '';
  return content
      .whereType<Map>()
      .map((part) => part['text']?.toString() ?? '')
      .join('\n');
}

/// A live `flutterpilot_server` subprocess speaking MCP over stdio.
///
/// Reads one JSON-RPC message per line from stdout, routes responses back to
/// the request that is waiting for them, answers the server's own `roots/list`
/// request, and keeps everything else (notifications, parse errors) for
/// [waitForMessage]. [kill] closes the streams and the process so a test never
/// leaks a subprocess.
class _Inspector {
  _Inspector._(this._process) {
    _stdoutSubscription = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
    _stderrSubscription = _process.stderr
        .transform(utf8.decoder)
        .listen((_) {});
  }

  /// Starts the server from the package root and wires up the transport.
  ///
  /// `FLUTTERPILOT_LIST_ALL_TOOLS` makes `tools/list` return every registered
  /// tool, so Matrix 2 audits the whole surface (including the native tools a
  /// dynamic list would hide until a device is attached).
  static Future<_Inspector> start() async {
    final entrypoint = File('bin/flutterpilot_server.dart');
    if (!entrypoint.existsSync()) {
      fail(
        'bin/flutterpilot_server.dart not found from ${Directory.current.path}; '
        'run "dart test" from packages/flutterpilot_server.',
      );
    }
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        'run',
        'bin/flutterpilot_server.dart',
        '--log-level',
        'severe',
        '--no-call-log',
      ],
      workingDirectory: Directory.current.path,
      environment: const {'FLUTTERPILOT_LIST_ALL_TOOLS': '1'},
    );
    return _Inspector._(process);
  }

  final Process _process;
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;

  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _received = <Map<String, dynamic>>[];
  var _nextId = 0;

  /// The `initialize` result, once [initialize] has run.
  Map<String, dynamic> get initializeResult => _initializeResult!;
  Map<String, dynamic>? _initializeResult;

  /// Performs the `initialize` handshake and the `notifications/initialized`
  /// follow-up, then proves the lifecycle reached `ready` with a round trip
  /// (the server refuses `tools/list` until the notification is processed).
  Future<void> initialize() async {
    final response = await request('initialize', {
      'protocolVersion': '2025-11-25',
      'capabilities': {
        'roots': <String, dynamic>{},
        'sampling': <String, dynamic>{},
        'experimental': <String, dynamic>{},
      },
      'clientInfo': {
        'name': 'flutterpilot-protocol-inspector',
        'version': '1.0.0',
      },
    });
    expect(response['error'], isNull, reason: '$response');
    _initializeResult = response['result'] as Map<String, dynamic>;
    notify('notifications/initialized');
    final ready = await request('tools/list');
    expect(
      ready['error'],
      isNull,
      reason: 'initialized notification not processed: $ready',
    );
  }

  /// The tools `tools/list` returns.
  Future<List<Map<String, dynamic>>> tools() async {
    final response = await request('tools/list');
    expect(response['error'], isNull, reason: '$response');
    final result = response['result'] as Map<String, dynamic>;
    return (result['tools'] as List).cast<Map<String, dynamic>>();
  }

  /// Sends a request and completes with its JSON-RPC response.
  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _write({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    return completer.future.timeout(const Duration(seconds: 30));
  }

  /// Sends a notification (no response expected).
  void notify(String method, [Map<String, dynamic>? params]) =>
      _write({'jsonrpc': '2.0', 'method': method, 'params': ?params});

  /// Writes a raw line, for framing tests that need bytes the builder would not
  /// produce (malformed JSON, a request with no method).
  void sendRaw(String line) => _process.stdin.writeln(line);

  /// Waits for an unsolicited message (a notification, a parse error, a
  /// server-to-client request) matching [matches].
  Future<Map<String, dynamic>> waitForMessage(
    bool Function(Map<String, dynamic> response) matches, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final message in _received) {
        if (matches(message)) return message;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail(
      'Timed out after $timeout waiting for a message. Received:\n'
      '${_received.map(jsonEncode).join('\n')}',
    );
  }

  /// Closes the transport and the subprocess.
  Future<void> kill() async {
    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
    _process.kill();
    await _process.exitCode;
  }

  void _onLine(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return; // The server never writes non-JSON to stdout.
    }
    if (decoded is! Map<String, dynamic>) return;
    final id = decoded['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer != null) {
        completer.complete(decoded);
        return;
      }
    }
    // A server-to-client request (the handshake's roots/list). Answer it so the
    // server is not left waiting, then keep it for inspection.
    if (decoded.containsKey('method') && id != null) {
      _answerServerRequest(decoded);
    }
    _received.add(decoded);
  }

  void _answerServerRequest(Map<String, dynamic> request) {
    final result = request['method'] == 'roots/list'
        ? {'roots': <Object>[]}
        : <String, dynamic>{};
    _write({'jsonrpc': '2.0', 'id': request['id'], 'result': result});
  }

  void _write(Map<String, dynamic> message) =>
      _process.stdin.writeln(jsonEncode(message));
}
