// Tests for the raw-client stdout hygiene detector (task 03).
//
// The detector is unit-tested on synthesized lines **and** end-to-end against a
// deliberately noisy fake server, so "the server never writes non-JSON to
// stdout" is an assertion a regression can fail, not a comment.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/stdout_hygiene.dart';

void main() {
  group('StdoutHygiene', () {
    test('accepts responses and notifications', () {
      final hygiene = StdoutHygiene();
      expect(hygiene.add('{"jsonrpc":"2.0","id":1,"result":{}}'), isNotNull);
      expect(
        hygiene.add('{"jsonrpc":"2.0","id":2,"error":{"code":-32601}}'),
        isNotNull,
      );
      expect(
        hygiene.add('{"jsonrpc":"2.0","method":"notifications/initialized"}'),
        isNotNull,
      );
      // A parse error cannot name an `id`; the spec says its `id` is null and
      // mcp_dart omits the member. The reply is still a protocol message.
      expect(
        hygiene.add(
          '{"jsonrpc":"2.0","error":{"code":-32700,"message":"Parse error"}}',
        ),
        isNotNull,
      );
      expect(hygiene.add('   '), isNull); // a blank line is not a violation
      expect(hygiene.clean, isTrue);
      expect(hygiene.lines, 4);
    });

    test('flags a non-JSON line', () {
      final hygiene = StdoutHygiene()..add('Starting server...');
      expect(hygiene.clean, isFalse);
      expect(hygiene.nonJson, hasLength(1));
      expect(hygiene.notProtocol, isEmpty);
      expect(hygiene.problem, contains('non-JSON'));
    });

    test('flags JSON that is not a JSON-RPC 2.0 message', () {
      for (final line in [
        '42', // a scalar
        '[1,2]', // an array
        '{"id":1,"result":{}}', // no jsonrpc
        '{"jsonrpc":"2.0","id":1}', // no result/error/method
        '{"jsonrpc":"2.0"}', // nothing at all
      ]) {
        final hygiene = StdoutHygiene()..add(line);
        expect(hygiene.notProtocol, hasLength(1), reason: line);
        expect(hygiene.nonJson, isEmpty, reason: line);
      }
    });
  });

  group('BoundedStderr', () {
    test('keeps only the first maxLines and reports truncation', () {
      final buffer = BoundedStderr(maxLines: 2);
      for (var i = 0; i < 5; i++) {
        buffer.add('line $i');
      }
      expect(buffer.lines, ['line 0', 'line 1']);
      expect(buffer.totalLines, 5);
      expect(buffer.truncated, isTrue);
    });

    test('redacts token-shaped values and bounds line length', () {
      final bearer = BoundedStderr.redact(
        'Authorization: Bearer abcdefghijklmnopqrstuvwxyz',
      );
      expect(bearer.toLowerCase(), contains('bearer'));
      expect(bearer, isNot(contains('abcdefghijklmnopqrstuvwxyz')));

      final key = BoundedStderr.redact('api_key: "supersecretvalue123"');
      expect(key, contains('api_key'));
      expect(key, isNot(contains('supersecretvalue123')));

      final openai = BoundedStderr.redact('token sk-abcdefghijklmnopqrstuvwx');
      expect(openai, isNot(contains('sk-abcdefghijklmnopqrstuvwx')));

      final long = BoundedStderr.redact('x' * 1000);
      expect(long.length, lessThanOrEqualTo(400));
      expect(long, endsWith('...'));
    });
  });

  group('against a live noisy server', () {
    late Process process;
    late StdoutHygiene hygiene;
    late StreamSubscription<String> subscription;
    final received = <Map<String, dynamic>>[];

    setUp(() async {
      received.clear();
      hygiene = StdoutHygiene();
      process = await Process.start(Platform.resolvedExecutable, [
        'test/fixtures/noisy_stdio_server.dart',
      ]);
      subscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final message = hygiene.add(line);
            if (message != null) received.add(message);
          });
    });

    tearDown(() async {
      await subscription.cancel();
      process.kill();
      await process.exitCode;
    });

    Future<Map<String, dynamic>> rpc(String method) async {
      received.clear();
      process.stdin.writeln(
        jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method}),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        final match = received.where((message) => message['id'] == 1).toList();
        if (match.isNotEmpty) return match.last;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('no reply to $method within 10s');
    }

    test('detects a banner printed before the handshake', () async {
      final response = await rpc('initialize');
      expect(response['result'], isNotNull);
      // The banner was the first stdout line; the detector caught it.
      expect(hygiene.nonJson, isNotEmpty);
      expect(hygiene.clean, isFalse);
    });

    test('detects a non-JSON line between two valid messages', () async {
      await rpc('initialize');
      final before = hygiene.nonJson.length;
      await rpc('noisy/nonJson');
      expect(hygiene.nonJson.length, greaterThan(before));
    });

    test('detects a message with no jsonrpc member', () async {
      await rpc('initialize');
      final before = hygiene.notProtocol.length;
      process.stdin.writeln(
        jsonEncode({'jsonrpc': '2.0', 'id': 2, 'method': 'noisy/notProtocol'}),
      );
      // The malformed reply is rejected by the detector, so it never reaches
      // `received`; wait on the violation list itself.
      await _waitFor(() => hygiene.notProtocol.length > before);
      expect(hygiene.notProtocol.length, greaterThan(before));
    });
  });
}

/// Waits up to ~10 seconds for [condition].
Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('condition was not met within 10s');
}
