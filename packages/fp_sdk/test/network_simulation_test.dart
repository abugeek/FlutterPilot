import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fp_sdk/fp_sdk.dart';

void main() {
  late HttpServer server;
  late Uri url;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) => r.response.close());
    url = Uri.parse('http://127.0.0.1:${server.port}/');
    NetworkSimulation.install();
  });

  tearDown(() async {
    NetworkSimulation.set(offline: false);
    await server.close(force: true);
  });

  test('offline fails a dart:io request before it is sent', () async {
    NetworkSimulation.set(offline: true);
    await expectLater(
      HttpClient().getUrl(url),
      throwsA(isA<SocketException>()),
    );
  });

  test('latency holds a dart:io request open', () async {
    NetworkSimulation.set(
      offline: false,
      latency: const Duration(milliseconds: 300),
    );
    final started = DateTime.now();
    final req = await HttpClient().getUrl(url);
    await (await req.close()).drain<void>();
    expect(
      DateTime.now().difference(started).inMilliseconds,
      greaterThanOrEqualTo(280),
    );
  });

  test('normal sends it straight away', () async {
    final started = DateTime.now();
    final req = await HttpClient().get('127.0.0.1', server.port, '/');
    await (await req.close()).drain<void>();
    expect(DateTime.now().difference(started).inMilliseconds, lessThan(250));
  });
}
