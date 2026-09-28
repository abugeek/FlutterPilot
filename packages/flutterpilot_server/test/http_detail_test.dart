import 'dart:convert';

import 'package:flutterpilot_server/src/http_detail.dart';
import 'package:test/test.dart';

void main() {
  test('duration runs until the response ended, not the request', () {
    // The top-level endTime is when the request was sent (310 ms); the
    // response finished at 529 ms.
    expect(
      durationMs({
        'startTime': 1000000,
        'endTime': 1310000,
        'response': {'endTime': 1529000},
      }),
      529,
    );
    expect(durationMs({'startTime': 1, 'endTime': 2}), isNull);
  });

  test('credential headers are masked', () {
    final lines = headerLines({
      'Authorization': ['Bearer abc.def'],
      'cookie': ['sid=1'],
      'content-type': ['application/json'],
    });
    expect(lines, [
      'Authorization: •••',
      'cookie: •••',
      'content-type: application/json',
    ]);
  });

  test('JSON bodies: secrets masked at any depth, the rest kept', () {
    final body = describeBody(
      utf8.encode(
        jsonEncode({
          'email': 'a@b.c',
          'password': 'hunter2',
          'auth': {'access_token': 'xyz', 'expires': 3600},
          'items': [
            {'apiKey': 'k', 'id': 1},
          ],
        }),
      ),
      'application/json; charset=utf-8',
    )!;
    expect(body, isNot(contains('hunter2')));
    expect(body, isNot(contains('xyz')));
    expect(body, contains('"password":"•••"'));
    expect(body, contains('"access_token":"•••"'));
    expect(body, contains('"expires":3600'));
    expect(body, contains('"apiKey":"•••"'));
    expect(body, contains('"email":"a@b.c"'));
  });

  test('form bodies mask secret fields', () {
    expect(
      describeBody(
        utf8.encode('user=ann&password=hunter2&remember=1'),
        'application/x-www-form-urlencoded',
      ),
      'user=ann&password=•••&remember=1',
    );
  });

  test('binary, non-UTF-8 and long bodies', () {
    expect(
      describeBody([1, 2, 3], 'image/png'),
      '3 bytes of image/png (binary, not shown)',
    );
    expect(
      describeBody([0xff, 0xfe, 0x00], null),
      '3 bytes (not UTF-8 text, not shown)',
    );
    final long = describeBody(utf8.encode('x' * 5000), 'text/plain', max: 100)!;
    expect(long, startsWith('x' * 100));
    expect(long, contains('4900 more characters; 5000 bytes in all'));
    expect(describeBody(const [], 'text/plain'), isNull);
  });

  test('a request in full', () {
    final text = formatRequestDetail({
      'method': 'POST',
      'uri': 'https://api.test/login',
      'startTime': 0,
      'events': [
        {'event': 'Connection established', 'timestamp': 40000},
        {'event': 'Waiting (TTFB)', 'timestamp': 250000},
      ],
      'request': {
        'headers': {
          'content-type': ['application/json'],
          'authorization': ['Bearer t'],
        },
      },
      'requestBody': utf8.encode('{"user":"ann","password":"p"}'),
      'response': {
        'statusCode': 401,
        'reasonPhrase': 'Unauthorized',
        'endTime': 300000,
        'headers': {
          'content-type': ['application/json'],
        },
        'redirects': [],
      },
      'responseBody': utf8.encode('{"error":"bad credentials"}'),
    }, number: 7);
    expect(
      text,
      startsWith('#7 POST https://api.test/login → 401 Unauthorized in 300 ms'),
    );
    expect(
      text,
      contains(
        'Timeline: Connection established +40 ms, Waiting (TTFB) +250 ms',
      ),
    );
    expect(text, contains('  authorization: •••'));
    expect(text, contains('Request body: {"user":"ann","password":"•••"}'));
    expect(text, contains('Response body: {"error":"bad credentials"}'));
  });

  test('a failed request shows its error and no response', () {
    final text = formatRequestDetail({
      'method': 'GET',
      'uri': 'https://down.test/',
      'startTime': 0,
      'request': {
        'headers': <String, dynamic>{},
        'error': 'SocketException: Connection refused',
      },
    }, number: 1);
    expect(text, contains('→ no response'));
    expect(text, contains('Error: SocketException: Connection refused'));
  });
}
