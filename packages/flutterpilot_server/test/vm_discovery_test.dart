import 'dart:io';

import 'package:flutterpilot_server/src/vm_discovery.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late HttpServer live;
  late String liveUri;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fp_discovery');
    live = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    live.listen((r) => r.response.close());
    liveUri = 'ws://127.0.0.1:${live.port}/abc=/ws';
  });

  tearDown(() async {
    await live.close(force: true);
    await tmp.delete(recursive: true);
  });

  File writeUri(String project, String uri, {DateTime? modified}) {
    final f = File(p.join(tmp.path, project, VmDiscoveryService.uriFile))
      ..createSync(recursive: true)
      ..writeAsStringSync(uri);
    if (modified != null) f.setLastModifiedSync(modified);
    return f;
  }

  test('finds an app nested in a workspace root', () async {
    writeUri('apps/mobile', liveUri);
    expect(await VmDiscoveryService.discover(roots: [tmp]), liveUri);
  });

  test('skips files naming a port nothing answers on', () async {
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = dead.port;
    await dead.close();
    writeUri('old', 'ws://127.0.0.1:$deadPort/x=/ws', modified: DateTime.now());
    writeUri(
      'current',
      liveUri,
      modified: DateTime.now().subtract(const Duration(hours: 1)),
    );
    expect(await VmDiscoveryService.discover(roots: [tmp]), liveUri);
  });

  test('prefers the most recently launched app', () async {
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    other.listen((r) => r.response.close());
    addTearDown(() => other.close(force: true));
    final otherUri = 'ws://127.0.0.1:${other.port}/def=/ws';
    writeUri(
      'a',
      liveUri,
      modified: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    writeUri('b', otherUri, modified: DateTime.now());
    expect(await VmDiscoveryService.discover(roots: [tmp]), otherUri);
  });

  test('does not look into build output, hidden folders or too deep', () {
    writeUri('build/x', liveUri);
    writeUri('.hidden/x', liveUri);
    writeUri('node_modules/x', liveUri);
    writeUri('a/b/c/d', liveUri);
    expect(VmDiscoveryService.findUriFiles(tmp), isEmpty);
  });

  test("doesn't descend into a project's platform folders", () {
    File(p.join(tmp.path, 'app', 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: app');
    writeUri('app/ios/x', liveUri);
    // A folder named web that is its own app (monorepo) is still searched.
    writeUri('web', liveUri);
    expect(
      VmDiscoveryService.findUriFiles(
        tmp,
      ).map((f) => p.relative(f.path, from: tmp.path)),
      [p.join('web', VmDiscoveryService.uriFile)],
    );
  });

  test('nothing found without roots', () async {
    expect(await VmDiscoveryService.discover(), isNull);
  });
}
