import 'dart:convert';
import 'dart:io';

import 'package:flutterpilot_server/src/dtd_discovery.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fp_dtd_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('instancesFromDisk reads instance files from directory', () {
    final dtdDir = Directory(p.join(tmp.path, 'dtd'))..createSync();
    final file = File(p.join(dtdDir.path, '12345'))..writeAsStringSync(
      jsonEncode({
        'wsUri': 'ws://127.0.0.1:8181/abc=',
        'workspaceRoot': '/test/project',
        'epoch': 1700000000000,
        'pid': 12345,
      }),
    );
    expect(file.existsSync(), isTrue);

    final instances = DtdDiscovery.instancesFromDisk([dtdDir]);
    expect(instances, hasLength(1));
    expect(instances.first.wsUri, 'ws://127.0.0.1:8181/abc=');
    expect(instances.first.workspaceRoot, '/test/project');
    expect(
      instances.first.started.millisecondsSinceEpoch,
      1700000000000,
    );
  });

  test('instancesFromDisk ignores non-JSON files and non-existent dirs', () {
    final dtdDir = Directory(p.join(tmp.path, 'dtd'))..createSync();
    File(p.join(dtdDir.path, 'not_json')).writeAsStringSync('corrupted');
    final missingDir = Directory(p.join(tmp.path, 'missing'));

    final instances = DtdDiscovery.instancesFromDisk([dtdDir, missingDir]);
    expect(instances, isEmpty);
  });

  test('instancesFromDisk deduplicates same wsUri across directories', () {
    final dir1 = Directory(p.join(tmp.path, 'd1'))..createSync();
    final dir2 = Directory(p.join(tmp.path, 'd2'))..createSync();
    final json = jsonEncode({
      'wsUri': 'ws://127.0.0.1:8181/abc=',
      'workspaceRoot': '/test/project',
      'epoch': 1700000000000,
    });
    File(p.join(dir1.path, '1')).writeAsStringSync(json);
    File(p.join(dir2.path, '2')).writeAsStringSync(json);

    final instances = DtdDiscovery.instancesFromDisk([dir1, dir2]);
    expect(instances, hasLength(1));
  });
}
