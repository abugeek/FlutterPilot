import 'dart:convert';

import 'package:flutterpilot_server/flutterpilot_server.dart';
import 'package:mcp_dart/mcp_dart.dart'
    show ErrorCode, McpError, ReadResourceResult, TextResourceContents;
import 'package:test/test.dart';

/// Task 16: standard MCP resources. They must list the five resources, read
/// each one whether or not an app is connected, and fail an unknown URI the
/// way the protocol does — all without adding a byte to `tools/list`.
void main() {
  late FlutterPilotServer server;
  setUp(() => server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888'));

  String textOf(ReadResourceResult result) =>
      (result.contents.single as TextResourceContents).text;

  group('resources/list', () {
    test('registers the five standard resources', () {
      final list = server.resourceListJson();
      expect(list, hasLength(5));
      expect(list.map((r) => r['uri']).toList(), [
        'flutterpilot://app/summary',
        'flutterpilot://app/errors',
        'flutterpilot://app/widget-tree',
        'flutterpilot://app/logs',
        'flutterpilot://devices',
      ]);
      for (final resource in list) {
        expect(resource['name'], isNotEmpty);
        expect(resource['description'], isNotEmpty);
        expect(resource['mimeType'], anyOf('application/json', 'text/plain'));
      }
    });

    test('advertises resources with listChanged and subscribe', () {
      final capabilities = server.serverCapabilitiesJson();
      expect(capabilities['resources'], {
        'listChanged': true,
        'subscribe': true,
      });
      expect(capabilities['tools'], isNotNull);
    });
  });

  group('resources/read with no app connected', () {
    test('the JSON resources say so', () async {
      for (final uri in [
        'flutterpilot://app/summary',
        'flutterpilot://app/errors',
      ]) {
        final body =
            jsonDecode(textOf(await server.readResourceForTest(uri)))
                as Map<String, dynamic>;
        expect(body['connected'], isFalse, reason: uri);
        expect(body['message'], contains('No Flutter app'));
      }
    });

    test('the text resources say so', () async {
      for (final uri in [
        'flutterpilot://app/widget-tree',
        'flutterpilot://app/logs',
      ]) {
        expect(
          textOf(await server.readResourceForTest(uri)),
          contains('No Flutter app currently connected'),
          reason: uri,
        );
      }
    });

    test('the device fleet is still listed, but marked disconnected', () async {
      final body =
          jsonDecode(
                textOf(
                  await server.readResourceForTest('flutterpilot://devices'),
                ),
              )
              as Map<String, dynamic>;
      expect(body['connected'], isFalse);
      expect(body['total'], 0);
    });
  });

  group('resources/read with an app connected', () {
    // What the connected app would report; ResourceAppData lets the connected
    // branch run without a live VM service.
    const data = ResourceAppData(
      snapshot: {
        'route': {'current': '/checkout', 'stackDepth': 2},
        'lifecycle': 'resumed',
        'recentLogs': [
          {
            'level': 'info',
            'message': 'before connect',
            'logger': 'debugPrint',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
        ],
      },
      errors: {
        'sdkMode': 'sdk',
        'errors': [
          {
            'exception': 'Exception: boom',
            'widget': 'CheckoutPage',
            'stackTrace': '#0  main (package:app/checkout.dart:42:5)',
            'timestamp': '2026-01-01T00:00:01.000Z',
          },
        ],
      },
      widgetTree: {
        'tree': {
          'type': 'Scaffold',
          'children': [
            {'type': 'Text', 'key': 'greeting', 'text': 'Hello'},
          ],
        },
      },
      serverLogs: [
        {
          'level': 'info',
          'message': 'after connect',
          'logger': 'stdout',
          'timestamp': '2026-01-01T00:00:02.000Z',
        },
      ],
    );

    Future<Map<String, dynamic>> readJson(String uri) async =>
        jsonDecode(textOf(await server.readResourceForTest(uri, app: data)))
            as Map<String, dynamic>;

    test('app summary reports route and error count', () async {
      final body = await readJson('flutterpilot://app/summary');
      expect(body['connected'], isTrue);
      expect(body['route'], '/checkout');
      expect(body['routeDepth'], 2);
      expect(body['lifecycle'], 'resumed');
      expect(body['errorCount'], 1);
      expect(body['sdkMode'], 'sdk');
    });

    test('active errors carry location and freshness', () async {
      final body = await readJson('flutterpilot://app/errors');
      expect(body['connected'], isTrue);
      expect(body['count'], 1);
      final error = (body['errors'] as List).single as Map<String, dynamic>;
      expect(error['exception'], 'Exception: boom');
      expect(error['location'], 'package:app/checkout.dart:42:5');
      expect(error['freshness'], 'since-last-reload');
    });

    test('widget tree is compact text', () async {
      final text = textOf(
        await server.readResourceForTest(
          'flutterpilot://app/widget-tree',
          app: data,
        ),
      );
      expect(text, contains('Scaffold'));
      expect(text, contains('Text greeting "Hello"'));
    });

    test('logs merge pre-connect and active lines', () async {
      final text = textOf(
        await server.readResourceForTest('flutterpilot://app/logs', app: data),
      );
      expect(text, contains('before connect'));
      expect(text, contains('after connect'));
    });

    test('device fleet lists registered devices', () async {
      server.fleet.registerDevice('iphone', 'ws://127.0.0.1:8181/a=/ws');
      final body = await readJson('flutterpilot://devices');
      expect(body['connected'], isTrue);
      expect(body['total'], 1);
      expect((body['devices'] as List).map((d) => d['id']), contains('iphone'));
    });
  });

  test('an unknown resource URI is a resourceNotFound error', () async {
    await expectLater(
      server.readResourceForTest('flutterpilot://app/nope'),
      throwsA(
        isA<McpError>()
            .having((e) => e.code, 'code', ErrorCode.resourceNotFound.value)
            .having((e) => e.message, 'message', 'Resource not found'),
      ),
    );
  });

  /// Task 26: the dynamic resource templates. With no app connected both say
  /// so; with app data injected, a read returns the subtree/child keys and the
  /// navigation state. The real URI matching and dispatch over stdio is in
  /// mcp_protocol_compliance_test.dart.
  group('resource templates', () {
    Map<String, dynamic> body(ReadResourceResult result) =>
        jsonDecode(textOf(result)) as Map<String, dynamic>;

    test('with no app connected both templates say so', () async {
      for (final result in [
        await server.readWidgetResourceForTest('any_key'),
        await server.readRouteResourceForTest('current'),
      ]) {
        final json = body(result);
        expect(json['connected'], isFalse);
        expect(json['message'], contains('No Flutter app'));
      }
    });

    test('a widget read returns properties, subtree and child keys', () async {
      final json = body(
        await server.readWidgetResourceForTest(
          'checkout_form',
          app: const ResourceTemplateData(
            widgetProperties: {'type': 'Column', 'target': 'checkout_form'},
            widgetTree: {
              'tree': {
                'type': 'Column',
                'key': 'checkout_form',
                'children': [
                  {'type': 'Text', 'key': 'checkout_name', 'text': 'Name'},
                  {
                    'type': 'Row',
                    'key': 'checkout_email',
                    'children': [
                      {'type': 'Text', 'text': 'label without a key'},
                    ],
                  },
                ],
              },
            },
          ),
        ),
      );
      expect(json['connected'], isTrue);
      expect(json['found'], isTrue);
      expect(json['key'], 'checkout_form');
      expect((json['widget'] as Map)['type'], 'Column');
      expect(json['childKeys'], ['checkout_name', 'checkout_email']);
      expect((json['tree'] as Map)['type'], 'Column');
    });

    test('an unknown widget key is not found, not an error', () async {
      final json = body(
        await server.readWidgetResourceForTest(
          'nope',
          app: const ResourceTemplateData(),
        ),
      );
      expect(json['connected'], isTrue);
      expect(json['found'], isFalse);
      expect(json['key'], 'nope');
    });

    test(
      'a route read reports the stack, current route and parameters',
      () async {
        final json = body(
          await server.readRouteResourceForTest(
            'current',
            app: const ResourceTemplateData(
              navigationStack: {
                'stack': ['/', '/checkout'],
              },
              routerState: {
                'currentLocation': '/checkout',
                'canPop': true,
                'pathParameters': {'id': '42'},
                'queryParameters': {'tab': 'pay'},
                'matchedRoutes': [
                  {'matchedLocation': '/', 'route': 'home'},
                  {'matchedLocation': '/checkout', 'route': 'checkout'},
                ],
              },
            ),
          ),
        );
        expect(json['connected'], isTrue);
        expect(json['found'], isTrue);
        expect(json['requested'], 'current');
        expect(json['currentRoute'], '/checkout');
        expect(json['stack'], ['/', '/checkout']);
        expect(json['stackDepth'], 2);
        expect(json['goRouter'], isTrue);
        expect(json['canPop'], isTrue);
        expect(json['pathParameters'], {'id': '42'});
        expect(json['queryParameters'], {'tab': 'pay'});
        expect((json['route'] as Map)['route'], 'checkout');
      },
    );

    test(
      'a route not on the stack is not found, but the state is still read',
      () async {
        final json = body(
          await server.readRouteResourceForTest(
            '/missing',
            app: const ResourceTemplateData(
              navigationStack: {
                'stack': ['/', '/checkout'],
              },
            ),
          ),
        );
        expect(json['connected'], isTrue);
        expect(json['found'], isFalse);
        expect(json['requested'], '/missing');
        expect(json['currentRoute'], '/checkout');
        expect(json['goRouter'], isFalse);
        expect(json['route'], isNull);
        expect(json['pathParameters'], isEmpty);
      },
    );
  });
}
