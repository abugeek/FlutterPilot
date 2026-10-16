// Task 09: the MCP transport must come up before the app connection, and an
// app-scoped call made in that window must say "connecting" rather than a
// premature "no app found". The spec (§16) requires those semantics to be
// pinned by a test before the change ships.
import 'dart:async';
import 'dart:io';

import 'package:fp_server/fp_server.dart';
import 'package:test/test.dart';

import 'support/in_process_mcp_client.dart';

void main() {
  test('serves MCP before the app connection settles, and answers '
      '"connecting" meanwhile (task 09)', () async {
    final connection = Completer<void>();
    final projectRoot = Directory.systemTemp.createTempSync(
      'fp_startup_order_',
    );
    addTearDown(() => projectRoot.deleteSync(recursive: true));

    final server = FlutterPilotServer(
      projectRoot: projectRoot,
      callLog: false,
      // Hold the first connection open so the window is observable.
      debugInitialConnect: () => connection.future,
    );
    addTearDown(server.stop);

    final client = InProcessMcpClient();
    addTearDown(client.close);

    // start() must return while the connection is still pending: that is the
    // whole point — a client is not made to wait for discovery.
    await server
        .start(transport: client.transport)
        .timeout(const Duration(seconds: 5));
    expect(connection.isCompleted, isFalse);

    final init = await client.initialize();
    expect((init['result'] as Map)['serverInfo'], isA<Map>());

    final tools = await client.request('tools/list');
    expect((tools['result'] as Map)['tools'] as List, isNotEmpty);

    // An app-scoped call in the window is retryable "connecting", not "no app".
    final pending = await client.callTool('get_errors');
    expect((pending['result'] as Map)['isError'], isTrue);
    expect(InProcessMcpClient.textOf(pending), contains('[reconnecting]'));
    expect(InProcessMcpClient.textOf(pending), contains('still connecting'));

    // Once the connection settles with no app, the same call says so.
    connection.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final settled = await client.callTool('get_errors');
    final settledText = InProcessMcpClient.textOf(settled);
    expect(settledText, isNot(contains('still connecting')));
    expect(settledText, contains('No running Flutter app found'));
  });

  test('a shutdown during the pending first connection settles cleanly '
      '(task 09)', () async {
    final connection = Completer<void>();
    final projectRoot = Directory.systemTemp.createTempSync('fp_startup_stop_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final server = FlutterPilotServer(
      projectRoot: projectRoot,
      callLog: false,
      debugInitialConnect: () => connection.future,
    );
    final client = InProcessMcpClient();
    addTearDown(client.close);

    await server.start(transport: client.transport);
    // stop() must not wait on (or race) the in-flight first connection.
    final stopped = server.stop();
    connection.complete();
    await stopped.timeout(const Duration(seconds: 5));
  });
}
