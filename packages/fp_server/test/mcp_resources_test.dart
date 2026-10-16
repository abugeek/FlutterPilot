import 'dart:convert';

import 'package:fp_server/fp_server.dart';
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

  /// Task 06: a resource reads only what it needs. A fake connection stands in
  /// for the app so the read plans are proven — with call counts and fault
  /// injection — without a running VM service.
  group('read plans (task 06)', () {
    late FakeResourceConnection connection;
    setUp(() {
      connection = FakeResourceConnection(
        responses: {
          'ext.flutterpilot.getAppSnapshot': {
            'route': {'current': '/home', 'stackDepth': 1},
            'lifecycle': 'resumed',
            'recentLogs': [
              {'level': 'info', 'message': 'hello', 'logger': 'debugPrint'},
            ],
          },
          'ext.flutterpilot.getErrors': {'sdkMode': 'sdk', 'errors': []},
          'ext.flutterpilot.getWidgetTree': {
            'tree': {'type': 'Scaffold', 'children': []},
          },
        },
      );
      server.resourceAppConnectionForTest = connection;
    });
    tearDown(() => server.resourceAppConnectionForTest = null);

    test(
      'the widget tree is fetched only by the widget-tree resource',
      () async {
        await server.readResourceForTest('flutterpilot://app/widget-tree');
        expect(connection.calls, ['ext.flutterpilot.getWidgetTree']);
      },
    );

    test('the summary reads the snapshot and errors, never the tree', () async {
      await server.readResourceForTest('flutterpilot://app/summary');
      expect(connection.calls, [
        'ext.flutterpilot.getAppSnapshot',
        'ext.flutterpilot.getErrors',
      ]);
    });

    test('errors, logs and the fleet read one thing each', () async {
      await server.readResourceForTest('flutterpilot://app/errors');
      expect(connection.calls, ['ext.flutterpilot.getErrors']);
      connection.calls.clear();
      await server.readResourceForTest('flutterpilot://app/logs');
      expect(connection.calls, ['ext.flutterpilot.getAppSnapshot']);
      connection.calls.clear();
      await server.readResourceForTest('flutterpilot://devices');
      expect(
        connection.calls,
        isEmpty,
        reason: 'fleet reads make zero app calls',
      );
    });

    test('the fleet is described as connected with zero app calls', () async {
      server.fleet.registerDevice('iphone', 'ws://127.0.0.1:8181/a=/ws');
      final body =
          jsonDecode(
                textOf(
                  await server.readResourceForTest('flutterpilot://devices'),
                ),
              )
              as Map<String, dynamic>;
      expect(body['connected'], isTrue);
      expect(body['total'], 1);
      expect(connection.calls, isEmpty);
    });

    test('no connection means no app call at all', () async {
      connection.connected = false;
      final body =
          jsonDecode(
                textOf(
                  await server.readResourceForTest(
                    'flutterpilot://app/summary',
                  ),
                ),
              )
              as Map<String, dynamic>;
      expect(body['connected'], isFalse);
      expect(connection.calls, isEmpty);
    });

    test('a full sweep of all five resources makes five app calls', () async {
      for (final uri in const [
        'flutterpilot://app/summary',
        'flutterpilot://app/errors',
        'flutterpilot://app/widget-tree',
        'flutterpilot://app/logs',
        'flutterpilot://devices',
      ]) {
        await server.readResourceForTest(uri);
      }
      // Before task 06 every read gathered the snapshot, the errors and the
      // tree: five resources x three = fifteen calls, tree included everywhere.
      expect(connection.calls, hasLength(5));
      expect(
        connection.calls.where((e) => e == 'ext.flutterpilot.getWidgetTree'),
        hasLength(1),
      );
    });

    test('a zero-code error list reports its mode', () async {
      connection.responses['ext.flutterpilot.getErrors'] = {
        'sdkMode': 'zero-code',
        'errors': const [],
      };
      final body =
          jsonDecode(
                textOf(
                  await server.readResourceForTest('flutterpilot://app/errors'),
                ),
              )
              as Map<String, dynamic>;
      expect(body['sdkMode'], 'zero-code');
      expect(body['count'], 0);
      expect(body.containsKey('errorsUnavailable'), isFalse);
    });
  });

  group('fault independence (task 06)', () {
    test('a failed tree read leaves the others intact', () async {
      final connection = FakeResourceConnection(
        responses: {
          'ext.flutterpilot.getAppSnapshot': {
            'route': {'current': '/home'},
            'recentLogs': [
              {'level': 'info', 'message': 'hello', 'logger': 'debugPrint'},
            ],
          },
          'ext.flutterpilot.getErrors': {'sdkMode': 'sdk', 'errors': []},
        },
        unavailable: {'ext.flutterpilot.getWidgetTree'},
      );
      server.resourceAppConnectionForTest = connection;
      addTearDown(() => server.resourceAppConnectionForTest = null);

      expect(
        textOf(
          await server.readResourceForTest('flutterpilot://app/widget-tree'),
        ),
        contains('No widget tree available'),
      );
      final summary =
          jsonDecode(
                textOf(
                  await server.readResourceForTest(
                    'flutterpilot://app/summary',
                  ),
                ),
              )
              as Map<String, dynamic>;
      expect(summary['route'], '/home');
      final errors =
          jsonDecode(
                textOf(
                  await server.readResourceForTest('flutterpilot://app/errors'),
                ),
              )
              as Map<String, dynamic>;
      expect(errors['count'], 0);
      expect(
        textOf(await server.readResourceForTest('flutterpilot://app/logs')),
        contains('hello'),
      );
    });

    test('an unavailable error list is not shown as clean', () async {
      final connection = FakeResourceConnection(
        responses: {
          'ext.flutterpilot.getAppSnapshot': {
            'route': {'current': '/home'},
          },
        },
        unavailable: {'ext.flutterpilot.getErrors'},
      );
      server.resourceAppConnectionForTest = connection;
      addTearDown(() => server.resourceAppConnectionForTest = null);

      final errors =
          jsonDecode(
                textOf(
                  await server.readResourceForTest('flutterpilot://app/errors'),
                ),
              )
              as Map<String, dynamic>;
      expect(errors['count'], 0);
      expect(errors['errorsUnavailable'], isTrue);
      final summary =
          jsonDecode(
                textOf(
                  await server.readResourceForTest(
                    'flutterpilot://app/summary',
                  ),
                ),
              )
              as Map<String, dynamic>;
      expect(summary['errorsUnavailable'], isTrue);
    });

    test('a healthy empty error list carries no unavailable flag', () async {
      final connection = FakeResourceConnection(
        responses: {
          'ext.flutterpilot.getErrors': {'sdkMode': 'sdk', 'errors': []},
        },
      );
      server.resourceAppConnectionForTest = connection;
      addTearDown(() => server.resourceAppConnectionForTest = null);
      final errors =
          jsonDecode(
                textOf(
                  await server.readResourceForTest('flutterpilot://app/errors'),
                ),
              )
              as Map<String, dynamic>;
      expect(errors['count'], 0);
      expect(errors.containsKey('errorsUnavailable'), isFalse);
    });
  });

  group('context pinning (task 06)', () {
    test('a device switch mid-read is reported, not blended', () async {
      final connection = FakeResourceConnection(
        responses: {
          'ext.flutterpilot.getAppSnapshot': {
            'route': {'current': '/home'},
          },
          'ext.flutterpilot.getErrors': {'sdkMode': 'sdk', 'errors': []},
        },
      );
      connection.onRead = (extension) {
        if (extension == 'ext.flutterpilot.getErrors') {
          connection.deviceId = 'other';
        }
      };
      server.resourceAppConnectionForTest = connection;
      addTearDown(() => server.resourceAppConnectionForTest = null);

      final body =
          jsonDecode(
                textOf(
                  await server.readResourceForTest(
                    'flutterpilot://app/summary',
                  ),
                ),
              )
              as Map<String, dynamic>;
      expect(body['contextChanged'], isTrue);
      expect(body['connected'], isTrue);
      expect(body['route'], isNull);
    });

    test('a reconnect mid-read is reported', () async {
      final connection = FakeResourceConnection(
        responses: {
          'ext.flutterpilot.getNavigationStack': {
            'stack': ['/'],
          },
          'ext.flutterpilot.getGoRouterState': {'currentLocation': '/'},
        },
      );
      connection.onRead = (extension) {
        if (extension == 'ext.flutterpilot.getGoRouterState') {
          connection.generation++;
        }
      };
      server.resourceAppConnectionForTest = connection;
      addTearDown(() => server.resourceAppConnectionForTest = null);

      final body =
          jsonDecode(textOf(await server.readRouteResourceForTest('current')))
              as Map<String, dynamic>;
      expect(body['contextChanged'], isTrue);
    });

    test('a text resource reports a changed context in words', () async {
      final connection = FakeResourceConnection(
        responses: {
          'ext.flutterpilot.getWidgetTree': {
            'tree': {'type': 'Scaffold'},
          },
        },
      );
      connection.onRead = (_) => connection.generation++;
      server.resourceAppConnectionForTest = connection;
      addTearDown(() => server.resourceAppConnectionForTest = null);

      expect(
        textOf(
          await server.readResourceForTest('flutterpilot://app/widget-tree'),
        ),
        contains('changed while this resource was being read'),
      );
    });
  });

  group('bounded and redacted rendering (task 06)', () {
    test(
      'the error list is capped with an accurate count and a note',
      () async {
        final many = [
          for (var i = 0; i < 60; i++) {'exception': 'Exception: boom $i'},
        ];
        final body =
            jsonDecode(
                  textOf(
                    await server.readResourceForTest(
                      'flutterpilot://app/errors',
                      app: ResourceAppData(
                        errors: {'sdkMode': 'sdk', 'errors': many},
                      ),
                    ),
                  ),
                )
                as Map<String, dynamic>;
        expect(body['count'], 60);
        expect(body['errors'], hasLength(50));
        expect(body['truncated'], isTrue);
        expect(body['note'], contains('Showing 50 of 60'));
      },
    );

    test('secrets in errors are masked and the JSON still parses', () async {
      final body =
          jsonDecode(
                textOf(
                  await server.readResourceForTest(
                    'flutterpilot://app/errors',
                    app: const ResourceAppData(
                      errors: {
                        'sdkMode': 'sdk',
                        'errors': [
                          {
                            'exception':
                                'Exception: request failed '
                                '(token=SUPERSECRET123)',
                          },
                        ],
                      },
                    ),
                  ),
                ),
              )
              as Map<String, dynamic>;
      final error = (body['errors'] as List).single as Map<String, dynamic>;
      expect(error['exception'], contains('<redacted>'));
      expect(error['exception'], isNot(contains('SUPERSECRET123')));
    });

    test('secrets in logs are masked', () async {
      final text = textOf(
        await server.readResourceForTest(
          'flutterpilot://app/logs',
          app: const ResourceAppData(
            serverLogs: [
              {
                'level': 'info',
                'message': 'Authorization: Bearer abcdef123456',
                'logger': 'stdout',
                'timestamp': '2026-01-01T00:00:00.000Z',
              },
            ],
          ),
        ),
      );
      expect(text, contains('<redacted>'));
      expect(text, isNot(contains('abcdef123456')));
    });

    test(
      'logs keep the newest entries and say how many were dropped',
      () async {
        final text = textOf(
          await server.readResourceForTest(
            'flutterpilot://app/logs',
            app: ResourceAppData(
              serverLogs: [
                for (var i = 0; i < 600; i++)
                  {
                    'level': 'info',
                    'message': 'line $i',
                    'logger': 'stdout',
                    'timestamp': '2026-01-01T00:00:00.000Z',
                  },
              ],
            ),
          ),
        );
        expect(text, contains('600 console entries'));
        expect(text, contains('Showing 500 of 600'));
        expect(text, isNot(contains('line 0')));
        expect(text, contains('line 599'));
      },
    );

    test('secrets in the widget tree text are masked', () async {
      final text = textOf(
        await server.readResourceForTest(
          'flutterpilot://app/widget-tree',
          app: const ResourceAppData(
            widgetTree: {
              'tree': {'type': 'Text', 'text': 'token=SUPERSECRET123'},
            },
          ),
        ),
      );
      expect(text, contains('<redacted>'));
      expect(text, isNot(contains('SUPERSECRET123')));
    });
  });

  group('templated reads (task 06)', () {
    test(
      'a key with spaces, slashes, quotes and Unicode is used verbatim',
      () async {
        final connection = FakeResourceConnection(
          responses: {
            'ext.flutterpilot.getWidgetProperties': {
              'type': 'Column',
              'target': 'a b/c"dé',
            },
          },
        );
        server.resourceAppConnectionForTest = connection;
        addTearDown(() => server.resourceAppConnectionForTest = null);
        const key = 'a b/c"dé';
        final result = await server.readWidgetResourceForTest(key);
        final body = jsonDecode(textOf(result)) as Map<String, dynamic>;
        expect(body['found'], isTrue);
        expect(body['key'], key);
        // The app is asked with the raw key, not the percent-encoded URI form.
        expect(connection.calls.first, 'ext.flutterpilot.getWidgetProperties');
        expect(connection.callArgs.first, {'key': key});
        // The echoed URI is a well-formed, percent-encoded URI.
        final uri = (result.contents.single as TextResourceContents).uri;
        expect(Uri.parse(uri).pathSegments.last, key);
      },
    );

    test('child keys are capped with a total', () async {
      final children = [
        for (var i = 0; i < 210; i++) {'type': 'Text', 'key': 'k$i'},
      ];
      final connection = FakeResourceConnection(
        responses: {
          'ext.flutterpilot.getWidgetProperties': {'type': 'Column'},
          'ext.flutterpilot.getWidgetTree': {
            'tree': {'type': 'Column', 'children': children},
          },
        },
      );
      server.resourceAppConnectionForTest = connection;
      addTearDown(() => server.resourceAppConnectionForTest = null);
      final body =
          jsonDecode(textOf(await server.readWidgetResourceForTest('root')))
              as Map<String, dynamic>;
      expect(body['childKeys'], hasLength(200));
      expect(body['childKeysTotal'], 210);
      expect(body['childKeysTruncated'], isTrue);
    });

    test('a route path with a query is echoed verbatim', () async {
      final connection = FakeResourceConnection(
        responses: {
          'ext.flutterpilot.getNavigationStack': {
            'stack': ['/'],
          },
        },
      );
      server.resourceAppConnectionForTest = connection;
      addTearDown(() => server.resourceAppConnectionForTest = null);
      const path = '/search?q=a b&lang=fr';
      final body =
          jsonDecode(textOf(await server.readRouteResourceForTest(path)))
              as Map<String, dynamic>;
      expect(body['requested'], path);
      expect(body['found'], isFalse);
    });
  });
}

/// A fake app connection (task 06): records every extension a resource read
/// makes and lets a test inject a missing extension, a failure, a device switch
/// or a reconnect — no VM service needed.
class FakeResourceConnection implements ResourceAppConnection {
  FakeResourceConnection({
    this.connected = true,
    this.deviceId = 'default',
    this.generation = 0,
    this.responses = const {},
    this.unavailable = const {},
  });

  @override
  bool connected;

  @override
  String deviceId;

  @override
  int generation;

  /// The data each extension returns when it is available.
  final Map<String, Map<String, dynamic>?> responses;

  /// Extensions that report as missing or failed.
  final Set<String> unavailable;

  /// Every extension read, in order.
  final List<String> calls = [];

  /// The arguments each [calls] entry was read with.
  final List<Map<String, dynamic>> callArgs = [];

  /// Runs just before a read returns; a test uses it to move the device or bump
  /// the generation while the resource is mid-read.
  void Function(String extension)? onRead;

  @override
  Future<ResourceExtensionRead> read(
    String extension,
    Map<String, dynamic> parameters,
  ) async {
    calls.add(extension);
    callArgs.add(parameters);
    onRead?.call(extension);
    if (unavailable.contains(extension)) {
      return const ResourceExtensionRead.unavailable();
    }
    return ResourceExtensionRead.available(responses[extension]);
  }
}
