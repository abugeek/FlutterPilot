// Regression tests for the fixture manifest and read-only preflight (task 00
// §8–11). No sibling checkout or network is required: git and file hashing are
// injected, so every branch (missing, mismatched, dirty, malformed) is
// deterministic.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/eval/src/fixtures.dart';

/// Builds a checkout tree under [root] for one fixture.
void writeCheckout(
  Directory root, {
  required String id,
  String head = 'abc123',
  String status = '',
  Map<String, String> scenarios = const {},
}) {
  final dir = Directory('${root.path}${Platform.pathSeparator}$id')
    ..createSync(recursive: true);
  File(
    '${dir.path}${Platform.pathSeparator}pubspec.yaml',
  ).writeAsStringSync('name: $id\n');
  for (final entry in scenarios.entries) {
    final file = File(
      '${dir.path}${Platform.pathSeparator}flutterpilot'
      '${Platform.pathSeparator}scenarios${Platform.pathSeparator}'
      '${entry.key}',
    )..createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fp_fixtures_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  FixtureManifest manifest(List<Map<String, dynamic>> fixtures) =>
      FixtureManifest.parse(
        jsonEncode({'schemaVersion': 1, 'fixtures': fixtures}),
      );

  group('manifest parsing', () {
    test('parses a valid manifest', () {
      final parsed = manifest([
        {
          'id': 'app',
          'revision': 'deadbeef',
          'plugins': ['dio'],
          'scenarioChecksums': {'base.json': 'aa'},
        },
      ]);
      final fixture = parsed.fixtures.single;
      expect(fixture.id, 'app');
      expect(fixture.revision, 'deadbeef');
      expect(fixture.plugins, ['dio']);
      expect(fixture.scenarioChecksums, {'base.json': 'aa'});
    });

    test('rejects malformed JSON, a missing version and no fixtures', () {
      expect(() => FixtureManifest.parse('{'), throwsFormatException);
      expect(
        () => FixtureManifest.parse('{"fixtures": []}'),
        throwsFormatException,
      );
      expect(
        () => FixtureManifest.parse('{"schemaVersion": 1, "fixtures": []}'),
        throwsFormatException,
      );
    });

    test('rejects a fixture without an id or revision, and duplicates', () {
      expect(
        () => manifest([
          {'revision': 'x'},
        ]),
        throwsFormatException,
      );
      expect(
        () => manifest([
          {'id': 'a'},
        ]),
        throwsFormatException,
      );
      expect(
        () => manifest([
          {'id': 'a', 'revision': 'x'},
          {'id': 'a', 'revision': 'y'},
        ]),
        throwsFormatException,
      );
    });
  });

  group('preflight', () {
    /// A git runner that answers from a per-directory table.
    GitRunner git(
      Map<String, String> heads, {
      Map<String, String> status = const {},
    }) => (dir, args) {
      final id = dir.split(RegExp(r'[\\/]')).last;
      if (args.first == 'rev-parse') {
        final head = heads[id];
        return head == null ? (128, '') : (0, head);
      }
      return (0, status[id] ?? '');
    };

    test('a matching checkout reports nothing', () {
      writeCheckout(root, id: 'app', scenarios: {'base.json': 'hello'});
      final issues = preflightFixtures(
        manifest([
          {
            'id': 'app',
            'revision': 'abc123',
            'scenarioChecksums': {'base.json': 'sha-of-hello'},
          },
        ]),
        fixturesRoot: root.path,
        runGit: git({'app': 'abc123'}),
        hashFile: (path) =>
            File(path).readAsStringSync() == 'hello' ? 'sha-of-hello' : 'other',
      );
      expect(issues, isEmpty);
    });

    test('a missing fixtures root is blocking', () {
      final issues = preflightFixtures(
        manifest([
          {'id': 'app', 'revision': 'abc123'},
        ]),
        fixturesRoot: '${root.path}${Platform.pathSeparator}nope',
        runGit: git(const {}),
      );
      expect(issues.single.level, FixtureIssueLevel.blocking);
      expect(issues.single.message, contains('fixtures root does not exist'));
    });

    test('a missing checkout is blocking', () {
      final issues = preflightFixtures(
        manifest([
          {'id': 'missing', 'revision': 'abc123'},
        ]),
        fixturesRoot: root.path,
        runGit: git(const {}),
      );
      expect(issues.single.level, FixtureIssueLevel.blocking);
      expect(issues.single.message, contains('checkout missing'));
    });

    test('a revision mismatch is blocking', () {
      writeCheckout(root, id: 'app');
      final issues = preflightFixtures(
        manifest([
          {'id': 'app', 'revision': 'expected9'},
        ]),
        fixturesRoot: root.path,
        runGit: git({'app': 'actual0'}),
      );
      expect(issues.single.level, FixtureIssueLevel.blocking);
      expect(issues.single.message, contains('revision mismatch'));
    });

    test('a dirty checkout is a warning, or blocking with requireClean', () {
      writeCheckout(root, id: 'app');
      final spec = manifest([
        {'id': 'app', 'revision': 'abc123'},
      ]);
      final warn = preflightFixtures(
        spec,
        fixturesRoot: root.path,
        runGit: git({'app': 'abc123'}, status: {'app': ' M lib/x.dart'}),
      );
      expect(warn.single.level, FixtureIssueLevel.warning);
      final blocking = preflightFixtures(
        spec,
        fixturesRoot: root.path,
        requireClean: true,
        runGit: git({'app': 'abc123'}, status: {'app': ' M lib/x.dart'}),
      );
      expect(blocking.single.level, FixtureIssueLevel.blocking);
    });

    test('a non-git checkout is a warning, not a silent pass', () {
      writeCheckout(root, id: 'app');
      final issues = preflightFixtures(
        manifest([
          {'id': 'app', 'revision': 'abc123'},
        ]),
        fixturesRoot: root.path,
        runGit: git(const {}),
      );
      expect(issues.single.level, FixtureIssueLevel.warning);
      expect(issues.single.message, contains('not a git checkout'));
    });

    test('a scenario hash mismatch or missing file is blocking', () {
      writeCheckout(root, id: 'app', scenarios: {'base.json': 'changed'});
      final mismatch = preflightFixtures(
        manifest([
          {
            'id': 'app',
            'revision': 'abc123',
            'scenarioChecksums': {'base.json': 'expected-hash'},
          },
        ]),
        fixturesRoot: root.path,
        runGit: git({'app': 'abc123'}),
        hashFile: (_) => 'actual-hash',
      );
      expect(mismatch.single.level, FixtureIssueLevel.blocking);
      expect(mismatch.single.message, contains('does not match'));

      writeCheckout(root, id: 'app2');
      final missing = preflightFixtures(
        manifest([
          {
            'id': 'app2',
            'revision': 'abc123',
            'scenarioChecksums': {'base.json': 'x'},
          },
        ]),
        fixturesRoot: root.path,
        runGit: git({'app2': 'abc123'}),
      );
      expect(missing.single.level, FixtureIssueLevel.blocking);
      expect(missing.single.message, contains('is missing'));
    });
  });

  group('the committed manifest', () {
    test('parses and names the three lab fixtures', () {
      final file = File(
        'tool/eval/fixtures/manifest.json'.replaceAll(
          '/',
          Platform.pathSeparator,
        ),
      );
      expect(file.existsSync(), isTrue, reason: file.path);
      final parsed = FixtureManifest.load(file);
      expect(parsed.schemaVersion, 1);
      expect(
        parsed.fixtures.map((f) => f.id),
        containsAll(['fp_lab_shop', 'fp_lab_notes', 'fp_lab_plain']),
      );
      for (final fixture in parsed.fixtures) {
        expect(fixture.revision.length, greaterThanOrEqualTo(7));
        expect(fixture.devices, isNotEmpty);
      }
    });
  });
}
