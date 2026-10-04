import 'dart:convert';
import 'dart:io';

import 'package:flutterpilot_server/src/dtd_discovery.dart';
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
      [p.normalize(p.join('web', VmDiscoveryService.uriFile))],
    );
  });

  test('nothing found without roots', () async {
    expect(await VmDiscoveryService.discover(), isNull);
  });

  group('Dart Tooling Daemon', () {
    DtdApp app(String workspace, {String? package, DateTime? started}) =>
        DtdApp(
          uri: liveUri,
          workspaceRoot: p.join(tmp.path, workspace),
          started: started ?? DateTime.now(),
          package: package,
        );

    test(
      'report says what each daemon answered and why an app counts',
      () async {
        // A daemon answering ConnectedApp.getVmServices with one app, or an
        // error (no ConnectedApp service).
        Future<HttpServer> daemon(Object reply) async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((r) async {
            final ws = await WebSocketTransformer.upgrade(r);
            await ws.first;
            ws.add(
              jsonEncode({'jsonrpc': '2.0', 'id': '1', ...?reply as Map?}),
            );
            await ws.close();
          });
          return server;
        }

        final withApp = await daemon({
          'result': {
            'vmServices': [
              {
                'uri': liveUri,
                'name': 'Kind: Flutter - Device: iPhone - Package: fixture',
              },
            ],
          },
        });
        final broken = await daemon({
          'error': {'code': -32601, 'message': 'Unknown method'},
        });
        Directory(p.join(tmp.path, 'fixture')).createSync();
        final listing = jsonEncode([
          for (final (server, root) in [
            (withApp, 'fixture'),
            (broken, 'other'),
          ])
            {
              'wsUri': 'ws://127.0.0.1:${server.port}/t=',
              'workspaceRoot': p.join(tmp.path, root),
              'epoch': 0,
            },
        ]);
        try {
          final lines = await DtdDiscovery.report([tmp], listing: listing);
          expect(
            lines.join('\n'),
            contains('fixture at $liveUri: under roots'),
          );
          expect(lines.join('\n'), contains(': true'));
          expect(lines.join('\n'), contains('Unknown method'));
          expect(
            await DtdDiscovery.report([
              Directory(p.join(tmp.path, 'x')),
            ], listing: listing),
            contains(endsWith(': false')),
          );
        } finally {
          await withApp.close(force: true);
          await broken.close(force: true);
        }
      },
    );

    test('parses the daemon list and the app names', () {
      final list = DtdDiscovery.parseInstances(
        '[{"wsUri":"ws://127.0.0.1:1/a=","epoch":1790674145402,"pid":1,'
        '"workspaceRoot":"/p/hn_reader"},{"wsUri":"ws://x","epoch":1,'
        '"workspaceRoot":""}]',
      );
      expect(list, hasLength(1));
      expect(list.single.workspaceRoot, '/p/hn_reader');
      expect(list.single.started.millisecondsSinceEpoch, 1790674145402);
      expect(DtdDiscovery.parseInstances('Found 1 instance'), isEmpty);

      final flutter = DtdDiscovery.appFrom(
        {
          'uri': 'ws://127.0.0.1:2/b=/ws',
          'name': 'Kind: Flutter - Device: macOS - Package: hn_reader',
        },
        '/p/hn_reader',
        DateTime(2026),
      )!;
      expect(flutter.package, 'hn_reader');
      expect(flutter.kind, 'Flutter');
      // A Dart script run from the IDE is not an app to drive.
      expect(
        DtdDiscovery.appFrom(
          {'uri': 'ws://x', 'name': 'Kind: Dart - Package: tool'},
          '/p',
          DateTime(2026),
        ),
        isNull,
      );
    });

    test('finds an app started with a plain flutter run', () async {
      expect(
        await VmDiscoveryService.discover(
          roots: [tmp],
          dtdApps: () async => [app('apps/mobile')],
        ),
        liveUri,
      );
    });

    test('matches a root given through a symlink', () {
      // The DTD records resolved paths; macOS temp folders are links.
      final link = Link(p.join(tmp.path, 'link'))
        ..createSync(p.join(tmp.path, 'real'));
      Directory(p.join(tmp.path, 'real', 'app')).createSync(recursive: true);
      final real = DtdApp(
        uri: liveUri,
        workspaceRoot: Directory(
          p.join(tmp.path, 'real', 'app'),
        ).resolveSymbolicLinksSync(),
        started: DateTime.now(),
      );
      expect(real.isUnder([Directory(link.path)]), isTrue);
    });

    test('ignores apps of other projects', () async {
      final elsewhere = Directory.systemTemp.createTempSync('fp_other');
      addTearDown(() => elsewhere.deleteSync(recursive: true));
      expect(
        await VmDiscoveryService.discover(
          roots: [elsewhere],
          dtdApps: () async => [app('mobile')],
        ),
        isNull,
      );
      // A root far above the project (a home folder) is not a workspace.
      expect(app('a/b/c/d').isUnder([tmp]), isFalse);
    });

    test("an IDE's workspace above the project matches by package", () {
      File(p.join(tmp.path, 'shop', 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: shop\n');
      final shop = Directory(p.join(tmp.path, 'shop'));
      expect(app('', package: 'shop').isUnder([shop]), isTrue);
      expect(app('', package: 'blog').isUnder([shop]), isFalse);
    });

    test('the newest launch wins across URI files and daemons', () async {
      final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      other.listen((r) => r.response.close());
      addTearDown(() => other.close(force: true));
      writeUri(
        'a',
        'ws://127.0.0.1:${other.port}/def=/ws',
        modified: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(
        await VmDiscoveryService.discover(
          roots: [tmp],
          dtdApps: () async => [app('b')],
        ),
        liveUri,
      );
    });
  });
}
