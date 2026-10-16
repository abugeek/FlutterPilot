// Fixture identity and read-only preflight (task 00 §8–11).
//
// The agent evals run against lab apps that live in sibling repositories. A
// run is only comparable if those fixtures are the exact revisions the suite
// was written for, so this module records each fixture's identity in a
// committed manifest and can check it before anything launches.
//
// `preflightFixtures` is read-only: it resolves paths, reads git metadata and
// hashes scenario files. It never starts an app, installs anything, or mutates
// a fixture. Every problem is reported; nothing is fixed silently.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// One reproducible fixture (a lab app).
class FixtureSpec {
  FixtureSpec({
    required this.id,
    required this.sourceLocation,
    required this.revision,
    required this.license,
    required this.plugins,
    required this.buildMode,
    required this.devices,
    required this.seedVersion,
    required this.scenarioChecksums,
    required this.expectedCapabilities,
  });

  /// The fixture id; also its directory name under the fixtures root.
  final String id;

  /// Where the fixture normally lives, relative to the repository root. Kept
  /// for documentation; resolution uses the configured fixtures root.
  final String sourceLocation;

  /// The exact commit the suite expects.
  final String revision;

  /// What the checkout's license is, as verified by the owner. Fixtures
  /// without a LICENSE file are recorded as undeclared, not assumed permissive.
  final String license;

  /// The FlutterPilot plugins the fixture registers.
  final List<String> plugins;

  /// The build mode the suite runs it in.
  final String buildMode;

  /// Devices the fixture is known to run on.
  final List<String> devices;

  /// The seed/scenario generation this revision corresponds to.
  final String seedVersion;

  /// sha256 of each `flutterpilot/scenarios/*.json`, by file name.
  final Map<String, String> scenarioChecksums;

  /// Tools the fixture is expected to register.
  final List<String> expectedCapabilities;

  Map<String, Object?> toJson() => {
    'id': id,
    'sourceLocation': sourceLocation,
    'revision': revision,
    'license': license,
    'plugins': plugins,
    'buildMode': buildMode,
    'devices': devices,
    'seedVersion': seedVersion,
    'scenarioChecksums': scenarioChecksums,
    'expectedCapabilities': expectedCapabilities,
  };

  static FixtureSpec fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) {
      final value = json[key];
      if (value == null) return const [];
      if (value is! List) {
        throw FormatException('fixture ${json['id']}: "$key" must be a list');
      }
      return value.map((e) => '$e').toList();
    }

    final id = json['id'];
    final revision = json['revision'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('a fixture has no "id"');
    }
    if (revision is! String || revision.isEmpty) {
      throw FormatException('fixture $id has no "revision"');
    }
    final checksums = json['scenarioChecksums'];
    return FixtureSpec(
      id: id,
      sourceLocation: '${json['sourceLocation'] ?? ''}',
      revision: revision,
      license: '${json['license'] ?? 'unknown'}',
      plugins: strings('plugins'),
      buildMode: '${json['buildMode'] ?? 'debug'}',
      devices: strings('devices'),
      seedVersion: '${json['seedVersion'] ?? 'unknown'}',
      scenarioChecksums: checksums is Map
          ? {for (final e in checksums.entries) '${e.key}': '${e.value}'}
          : const {},
      expectedCapabilities: strings('expectedCapabilities'),
    );
  }
}

/// The committed fixture manifest.
class FixtureManifest {
  FixtureManifest({required this.schemaVersion, required this.fixtures});

  final int schemaVersion;
  final List<FixtureSpec> fixtures;

  FixtureSpec? byId(String id) {
    for (final fixture in fixtures) {
      if (fixture.id == id) return fixture;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'fixtures': [for (final fixture in fixtures) fixture.toJson()],
  };

  /// Parses [text]. Throws [FormatException] when the manifest is malformed.
  static FixtureManifest parse(String text) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('fixture manifest is not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('fixture manifest must be a JSON object');
    }
    final json = decoded.cast<String, dynamic>();
    final version = json['schemaVersion'];
    if (version is! int) {
      throw const FormatException(
        'fixture manifest needs an int schemaVersion',
      );
    }
    final fixtures = json['fixtures'];
    if (fixtures is! List || fixtures.isEmpty) {
      throw const FormatException('fixture manifest has no "fixtures"');
    }
    final parsed = <FixtureSpec>[];
    final seen = <String>{};
    for (final fixture in fixtures) {
      if (fixture is! Map) {
        throw const FormatException('a "fixtures" entry is not an object');
      }
      final spec = FixtureSpec.fromJson(fixture.cast<String, dynamic>());
      if (!seen.add(spec.id)) {
        throw FormatException('duplicate fixture id "${spec.id}"');
      }
      parsed.add(spec);
    }
    return FixtureManifest(schemaVersion: version, fixtures: parsed);
  }

  static FixtureManifest load(File file) {
    if (!file.existsSync()) {
      throw FormatException('fixture manifest not found: ${file.path}');
    }
    return parse(file.readAsStringSync());
  }
}

/// How serious a preflight finding is.
enum FixtureIssueLevel {
  /// The run cannot be trusted; it must not start.
  blocking,

  /// The run can proceed, but is not baseline-grade (e.g. a dirty checkout).
  warning,
}

class FixtureIssue {
  FixtureIssue(this.fixtureId, this.level, this.message);

  /// The fixture id, or `(manifest)` for a manifest-level finding.
  final String fixtureId;
  final FixtureIssueLevel level;
  final String message;

  @override
  String toString() => '[${level.name}] $fixtureId: $message';
}

/// Runs git [args] in [directory]; returns (exitCode, stdout).
typedef GitRunner = (int, String) Function(String directory, List<String> args);

(int, String) defaultGit(String directory, List<String> args) {
  try {
    final result = Process.runSync('git', ['-C', directory, ...args]);
    return (result.exitCode, '${result.stdout}'.trim());
  } on ProcessException {
    return (-1, '');
  }
}

/// Checks [manifest] against the checkouts under [fixturesRoot] (a directory
/// that contains one subdirectory per fixture id).
///
/// Returns every issue found, blocking first. Read-only. [runGit] is injectable
/// for tests. When [requireClean] is true a dirty checkout is blocking; by
/// default it is a warning (the run is then marked non-baseline).
List<FixtureIssue> preflightFixtures(
  FixtureManifest manifest, {
  required String fixturesRoot,
  bool requireClean = false,
  GitRunner runGit = defaultGit,
  String Function(String path)? hashFile,
}) {
  final issues = <FixtureIssue>[];
  final hash = hashFile ?? _sha256OfFile;

  if (!Directory(fixturesRoot).existsSync()) {
    issues.add(
      FixtureIssue(
        '(manifest)',
        FixtureIssueLevel.blocking,
        'fixtures root does not exist: $fixturesRoot (pass --fixtures)',
      ),
    );
    return issues;
  }

  for (final fixture in manifest.fixtures) {
    final dir = '$fixturesRoot${Platform.pathSeparator}${fixture.id}';
    if (!Directory(dir).existsSync()) {
      issues.add(
        FixtureIssue(
          fixture.id,
          FixtureIssueLevel.blocking,
          'checkout missing at $dir',
        ),
      );
      continue;
    }
    if (!File('$dir${Platform.pathSeparator}pubspec.yaml').existsSync()) {
      issues.add(
        FixtureIssue(
          fixture.id,
          FixtureIssueLevel.blocking,
          'no pubspec.yaml at $dir — not a Flutter package',
        ),
      );
      continue;
    }

    final (code, head) = runGit(dir, ['rev-parse', 'HEAD']);
    if (code != 0 || head.isEmpty) {
      issues.add(
        FixtureIssue(
          fixture.id,
          FixtureIssueLevel.warning,
          'not a git checkout; the declared revision cannot be verified',
        ),
      );
    } else if (!head.startsWith(fixture.revision) &&
        !fixture.revision.startsWith(head)) {
      issues.add(
        FixtureIssue(
          fixture.id,
          FixtureIssueLevel.blocking,
          'revision mismatch: manifest ${fixture.revision}, checkout $head',
        ),
      );
    } else {
      final (_, status) = runGit(dir, ['status', '--porcelain']);
      if (status.isNotEmpty) {
        issues.add(
          FixtureIssue(
            fixture.id,
            requireClean
                ? FixtureIssueLevel.blocking
                : FixtureIssueLevel.warning,
            'checkout is dirty (${status.split('\n').length} changed '
            'entries); a dirty fixture makes a baseline non-reproducible',
          ),
        );
      }
    }

    for (final entry in fixture.scenarioChecksums.entries) {
      final file = File(
        '$dir${Platform.pathSeparator}flutterpilot'
        '${Platform.pathSeparator}scenarios${Platform.pathSeparator}'
        '${entry.key}',
      );
      if (!file.existsSync()) {
        issues.add(
          FixtureIssue(
            fixture.id,
            FixtureIssueLevel.blocking,
            'scenario ${entry.key} is missing',
          ),
        );
        continue;
      }
      final actual = hash(file.path);
      if (actual != entry.value) {
        issues.add(
          FixtureIssue(
            fixture.id,
            FixtureIssueLevel.blocking,
            'scenario ${entry.key} does not match the manifest '
            '(expected ${entry.value}, got $actual)',
          ),
        );
      }
    }
  }
  issues.sort(
    (a, b) => a.level == b.level
        ? a.fixtureId.compareTo(b.fixtureId)
        : (a.level == FixtureIssueLevel.blocking ? -1 : 1),
  );
  return issues;
}

String _sha256OfFile(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

/// The scenarios root of [fixtureDir] (`flutterpilot/scenarios`), or null.
Directory? scenarioDirOf(String fixtureDir) {
  final dir = Directory(
    '$fixtureDir${Platform.pathSeparator}flutterpilot'
    '${Platform.pathSeparator}scenarios',
  );
  return dir.existsSync() ? dir : null;
}

/// Computes the manifest [FixtureSpec.scenarioChecksums] for a checkout, so a
/// manifest can be regenerated from the real files instead of hand-typed.
Map<String, String> scenarioChecksumsOf(String fixtureDir) {
  final dir = scenarioDirOf(fixtureDir);
  if (dir == null) return const {};
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final file in files)
      file.uri.pathSegments.last: _sha256OfFile(file.path),
  };
}
