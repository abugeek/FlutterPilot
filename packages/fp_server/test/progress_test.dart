import 'dart:async';

import 'package:fp_server/fp_server.dart';
import 'package:fp_server/src/batch_nudge.dart';
import 'package:fp_server/src/progress.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class _TestAbortSignal implements AbortSignal {
  bool _aborted = false;
  final _controller = StreamController<void>.broadcast();

  void abort([dynamic reason]) {
    _aborted = true;
    _reason = reason;
    _controller.add(null);
  }

  dynamic _reason;

  @override
  bool get aborted => _aborted;

  @override
  dynamic get reason => _reason;

  @override
  Stream<void> get onAbort => _controller.stream;

  @override
  void throwIfAborted() {
    if (_aborted) throw StateError('aborted');
  }
}

void main() {
  group('ToolProgress', () {
    test(
      'sends nothing when the client did not pass a progressToken',
      () async {
        final sent = <JsonRpcNotification>[];
        final extra = RequestHandlerExtra(
          signal: _TestAbortSignal(),
          requestId: 1,
          sendNotification: (n, {relatedTask}) async => sent.add(n),
          sendRequest: <T extends BaseResultData>(req, fac, opts) =>
              throw UnimplementedError(),
        );
        final progress = ToolProgress(extra, total: 3);
        expect(progress.requested, isFalse);
        await progress.advance('Step 1/3');
        await progress.tick('Waiting');
        expect(sent, isEmpty);
      },
    );

    test(
      'emits strictly increasing progress values across shared reporters on one request',
      () async {
        final sent = <Map<String, dynamic>>[];
        final extra = RequestHandlerExtra(
          signal: _TestAbortSignal(),
          requestId: 2,
          meta: {'progressToken': 'tok-42'},
          sendNotification: (n, {relatedTask}) async =>
              sent.add(n.params ?? const {}),
          sendRequest: <T extends BaseResultData>(req, fac, opts) =>
              throw UnimplementedError(),
        );
        final outer = ToolProgress(extra, total: 4);
        final inner = ToolProgress(extra, total: 2);

        await outer.advance('Device A: step 1');
        await inner.advance('Nested step 1');
        await outer.advance('Device B: step 1');

        expect(sent.map((p) => p['progress']).toList(), [1.0, 2.0, 3.0]);
        expect(sent.every((p) => p['progressToken'] == 'tok-42'), isTrue);
        expect(sent.first['total'], 4.0);
        // When progress exceeds inner's smaller total (3 > 2), total is omitted
        // rather than reporting progress > total.
        final third = ToolProgress(extra, total: 2);
        await third.advance('After inner');
        expect(sent.last['progress'], 4.0);
        expect(sent.last.containsKey('total'), isFalse);
      },
    );

    test(
      'tick deduplicates unchanged messages within heartbeat window',
      () async {
        final sent = <Map<String, dynamic>>[];
        final extra = RequestHandlerExtra(
          signal: _TestAbortSignal(),
          requestId: 3,
          meta: {'progressToken': 7},
          sendNotification: (n, {relatedTask}) async =>
              sent.add(n.params ?? const {}),
          sendRequest: <T extends BaseResultData>(req, fac, opts) =>
              throw UnimplementedError(),
        );
        final progress = ToolProgress(
          extra,
          heartbeat: const Duration(hours: 1),
        );
        await progress.tick('Building: fetching packages');
        await progress.tick('Building: fetching packages');
        await progress.tick('Building: compiling the Android app');
        expect(sent.length, 2);
        expect(sent[0]['message'], 'Building: fetching packages');
        expect(sent[1]['message'], 'Building: compiling the Android app');
      },
    );

    test('cancellation is observed from the request AbortSignal', () {
      final signal = _TestAbortSignal();
      final extra = RequestHandlerExtra(
        signal: signal,
        requestId: 4,
        sendNotification: (n, {relatedTask}) async {},
        sendRequest: <T extends BaseResultData>(req, fac, opts) =>
            throw UnimplementedError(),
      );
      final progress = ToolProgress(extra);
      expect(progress.cancelled, isFalse);
      signal.abort('user cancelled');
      expect(progress.cancelled, isTrue);
    });
  });

  group('Setup steps in execute_action_chain and BatchNudge', () {
    test(
      'execute_action_chain accepts mock/network/settings steps in preflight',
      () {
        final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
        expect(
          server.checkArgumentsForTest('execute_action_chain', {
            'steps': [
              {
                'tool': 'mock_http_response',
                'arguments': {'urlPattern': '/api/items', 'statusCode': 500},
              },
              {
                'tool': 'simulate_network',
                'arguments': {'condition': 'offline'},
              },
              {
                'tool': 'set_app_settings',
                'arguments': {'themeMode': 'dark', 'textScale': 1.4},
              },
              {
                'tool': 'mock_platform_channel',
                'arguments': {
                  'channel': 'plugins.flutter.io/geolocator',
                  'result': {'latitude': 37.7, 'longitude': -122.4},
                },
              },
              {
                'tool': 'tap_widget',
                'arguments': {'key': 'Refresh'},
              },
            ],
          }),
          isNull,
        );
      },
    );

    test(
      'execute_action_chain stops before running steps when the request is already cancelled',
      () async {
        final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
        final signal = _TestAbortSignal()..abort('user cancelled');
        final sent = <Map<String, dynamic>>[];
        final extra = RequestHandlerExtra(
          signal: signal,
          requestId: 99,
          meta: {'progressToken': 'chain-tok'},
          sendNotification: (n, {relatedTask}) async =>
              sent.add(n.params ?? const {}),
          sendRequest: <T extends BaseResultData>(req, fac, opts) =>
              throw UnimplementedError(),
        );
        final res = await server.callToolForTest('execute_action_chain', {
          'steps': [
            {
              'tool': 'mock_http_response',
              'arguments': {'urlPattern': '/api/items', 'statusCode': 500},
            },
            {
              'tool': 'simulate_network',
              'arguments': {'condition': 'offline'},
            },
          ],
        }, extra: extra);
        expect(res.isError, isTrue);
        expect(sent, isEmpty);
        expect(res.structuredContent, {
          'passed': false,
          'completedSteps': 0,
          'totalSteps': 2,
          'failedStep': 1,
          'failureReason': 'Cancelled before running mock_http_response.',
        });
      },
    );

    test('BatchNudge counts consecutive mock_http_response calls', () {
      final nudge = BatchNudge();
      expect(nudge.after('mock_http_response', isError: false), isNull);
      expect(nudge.after('mock_http_response', isError: false), isNull);
      final third = nudge.after('mock_http_response', isError: false);
      expect(third, isNotNull);
      expect(third, contains('execute_action_chain'));
    });
  });

  group('get_debug_logs per-line bounding', () {
    test('clips oversized single-line log messages at 500 chars', () async {
      final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
      final huge = 'A' * 2000;
      server.recordDebugLogForTest(
        level: 'info',
        message: huge,
        logger: 'stdout',
        timestamp: '2026-10-17T12:00:00.000Z',
      );
      final result = await server.callToolForTest('get_debug_logs', {});
      final text = result.content.whereType<TextContent>().single.text;
      expect(text, contains('… (+1500 chars)'));
      expect(text.length, lessThan(800));
    });
  });
}
