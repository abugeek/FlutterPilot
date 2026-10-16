// Run identity and comparability (task 04 §12–§14).
//
// Two reports may only be compared when they describe the *same* measurement:
// the same model, device, platform, build mode, task definitions, fixtures and
// runner policy. A candidate server revision and its guidance/tool-schema
// hashes are *expected* to differ between a baseline and the change under test
// — those are reported, not rejected.
//
// Everything here is recorded so a later run can prove what it was: the task
// suite's content hash and ids, each fixture's revision/content/scenarios, the
// SDK versions, the pricing table version, and the policy that bounded the run.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'fixtures.dart';
import 'mcp_session.dart';
import 'tasks.dart';

/// sha256 of [text] as lowercase hex.
String sha256Text(String text) => sha256.convert(utf8.encode(text)).toString();

/// sha256 of the file at [path] as lowercase hex.
String sha256File(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

/// A stable hash of a tool list's model-facing projection: name, description
/// and input schema, in the order the server listed them. Two servers whose
/// tools differ by a byte hash differently, so a surface change is visible
/// even when the tool count is unchanged.
String canonicalToolSchemaHash(List<McpTool> tools) {
  final encoded = jsonEncode([
    for (final tool in tools)
      {
        'name': tool.name,
        'description': tool.description,
        'inputSchema': tool.inputSchema,
      },
  ]);
  return sha256Text(encoded);
}

/// The task suite a run selected: the suite file's content hash and the exact
/// ids run. Both must match for a comparison.
class TaskSuiteIdentity {
  const TaskSuiteIdentity({required this.hash, required this.ids});

  static const unknown = TaskSuiteIdentity(hash: 'unknown', ids: []);

  /// sha256 of the `tasks.yaml` bytes.
  final String hash;

  /// The selected task ids, sorted.
  final List<String> ids;

  Map<String, Object?> toJson() => {'hash': hash, 'ids': ids};

  static TaskSuiteIdentity fromJson(Map<String, dynamic> json) =>
      TaskSuiteIdentity(
        hash: '${json['hash']}',
        ids: [for (final id in (json['ids'] as List? ?? const [])) '$id'],
      );
}

/// Builds the identity of the [tasks] selected from a suite whose full text is
/// [suiteText].
TaskSuiteIdentity taskSuiteIdentity(
  List<EvalTask> tasks, {
  required String suiteText,
}) {
  final ids = tasks.map((t) => t.id).toList()..sort();
  return TaskSuiteIdentity(hash: sha256Text(suiteText), ids: ids);
}

/// One fixture (lab app) as it was actually on disk during the run.
class FixtureIdentity {
  const FixtureIdentity({
    required this.id,
    required this.manifestRevision,
    required this.checkoutRevision,
    required this.contentHash,
    required this.scenarioChecksums,
  });

  final String id;

  /// The revision the committed manifest expects.
  final String manifestRevision;

  /// The checkout's actual `git rev-parse --short HEAD`, or `unknown`.
  final String checkoutRevision;

  /// sha256 of the checkout's `pubspec.yaml` — a cheap content marker that
  /// changes when the app's dependencies or name change.
  final String contentHash;

  /// sha256 of every `flutterpilot/scenarios/*.json`, by file name.
  final Map<String, String> scenarioChecksums;

  Map<String, Object?> toJson() => {
    'id': id,
    'manifestRevision': manifestRevision,
    'checkoutRevision': checkoutRevision,
    'contentHash': contentHash,
    'scenarioChecksums': scenarioChecksums,
  };

  static FixtureIdentity fromJson(Map<String, dynamic> json) => FixtureIdentity(
    id: '${json['id']}',
    manifestRevision: '${json['manifestRevision']}',
    checkoutRevision: '${json['checkoutRevision']}',
    contentHash: '${json['contentHash']}',
    scenarioChecksums: {
      for (final e in ((json['scenarioChecksums'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    },
  );
}

/// Records a fixture's identity from [spec] (or null when the app is not in the
/// manifest) and its checkout at [appDir].
FixtureIdentity buildFixtureIdentity(
  FixtureSpec? spec,
  String appDir, {
  GitRunner runGit = defaultGit,
}) {
  final (code, head) = runGit(appDir, ['rev-parse', '--short', 'HEAD']);
  final pubspec = File('$appDir${Platform.pathSeparator}pubspec.yaml');
  return FixtureIdentity(
    id: spec?.id ?? _basename(appDir),
    manifestRevision: spec?.revision ?? 'undeclared',
    checkoutRevision: code == 0 && head.isNotEmpty ? head : 'unknown',
    contentHash: pubspec.existsSync() ? sha256File(pubspec.path) : 'missing',
    scenarioChecksums: scenarioChecksumsOf(appDir),
  );
}

String _basename(String path) {
  final normalised = path.replaceAll('\\', '/');
  final parts = normalised.split('/')..removeWhere((p) => p.isEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// Everything a report needs to decide whether two runs are comparable.
class RunIdentity {
  RunIdentity({
    required this.model,
    required this.device,
    this.platform = 'unknown',
    this.buildMode = 'debug',
    this.sdk = const {},
    TaskSuiteIdentity? taskSuite,
    this.fixtures = const {},
    this.policy = const {},
    this.pricingVersion = 'none',
  }) : taskSuite = taskSuite ?? TaskSuiteIdentity.unknown;

  final String model;

  /// The named device the app was driven on.
  final String device;

  /// `Platform.operatingSystem` of the host that ran the eval.
  final String platform;

  /// `debug` / `profile` / `release`.
  final String buildMode;

  /// `dart`, `flutter`, `os` versions.
  final Map<String, String> sdk;

  final TaskSuiteIdentity taskSuite;
  final Map<String, FixtureIdentity> fixtures;

  /// The runner policy that bounded the run (repeat, limits, spend, profile,
  /// server args). Only the keys in [policyKeys] decide comparability.
  final Map<String, Object?> policy;

  /// The pricing table's version tag, or `none`.
  final String pricingVersion;

  /// The policy keys that must match for a comparison to be valid.
  static const policyKeys = [
    'repeat',
    'allowDestructive',
    'profile',
    'serverArgs',
    'maxCalls',
    'maxTurns',
  ];

  Map<String, Object?> toJson() => {
    'model': model,
    'device': device,
    'platform': platform,
    'buildMode': buildMode,
    'sdk': sdk,
    'taskSuite': taskSuite.toJson(),
    'fixtures': {for (final e in fixtures.entries) e.key: e.value.toJson()},
    'policy': policy,
    'pricingVersion': pricingVersion,
  };

  static RunIdentity fromJson(Map<String, dynamic> json) => RunIdentity(
    model: '${json['model']}',
    device: '${json['device']}',
    platform: '${json['platform'] ?? 'unknown'}',
    buildMode: '${json['buildMode'] ?? 'debug'}',
    sdk: {
      for (final e in ((json['sdk'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    },
    taskSuite: json['taskSuite'] is Map
        ? TaskSuiteIdentity.fromJson(
            (json['taskSuite'] as Map).cast<String, dynamic>(),
          )
        : TaskSuiteIdentity.unknown,
    fixtures: {
      for (final e in ((json['fixtures'] as Map?) ?? const {}).entries)
        '${e.key}': FixtureIdentity.fromJson(
          (e.value as Map).cast<String, dynamic>(),
        ),
    },
    policy: {
      for (final e in ((json['policy'] as Map?) ?? const {}).entries)
        '${e.key}': e.value,
    },
    pricingVersion: '${json['pricingVersion'] ?? 'none'}',
  );

  /// Identities that differ in a way that makes a comparison meaningless. An
  /// empty list means [other] measures the same thing this does.
  List<String> hardMismatches(RunIdentity other) {
    final problems = <String>[];
    if (model != other.model) {
      problems.add('different models: $model vs ${other.model}');
    }
    if (device != other.device) {
      problems.add('different devices: $device vs ${other.device}');
    }
    if (platform != other.platform) {
      problems.add('different platforms: $platform vs ${other.platform}');
    }
    if (buildMode != other.buildMode) {
      problems.add('different build modes: $buildMode vs ${other.buildMode}');
    }
    if (taskSuite.hash != other.taskSuite.hash) {
      problems.add(
        'different task suites: ${taskSuite.hash} vs ${other.taskSuite.hash}',
      );
    }
    if (!_sameIds(taskSuite.ids, other.taskSuite.ids)) {
      problems.add(
        'different task sets: [${taskSuite.ids.join(', ')}] vs '
        '[${other.taskSuite.ids.join(', ')}]',
      );
    }
    for (final key in policyKeys) {
      final before = policy[key];
      final after = other.policy[key];
      if ('$before' != '$after') {
        problems.add('different policy "$key": $before vs $after');
      }
    }
    for (final id in {...fixtures.keys, ...other.fixtures.keys}) {
      final before = fixtures[id];
      final after = other.fixtures[id];
      if (before == null || after == null) {
        problems.add('$id is present in only one run');
        continue;
      }
      if (before.manifestRevision != after.manifestRevision ||
          before.checkoutRevision != after.checkoutRevision) {
        problems.add(
          '$id is at a different revision: '
          '${before.checkoutRevision} vs ${after.checkoutRevision}',
        );
      }
      if (before.contentHash != after.contentHash) {
        problems.add('$id has different contents');
      }
      if (jsonEncode(before.scenarioChecksums) !=
          jsonEncode(after.scenarioChecksums)) {
        problems.add('$id has different scenarios');
      }
    }
    return problems;
  }

  /// Identities expected to differ between a baseline and the change under
  /// test. Reported for review, never a refusal.
  List<String> expectedDifferences(RunIdentity other) {
    final lines = <String>[];
    for (final (name, a, b) in [
      ('dart', sdk['dart'], other.sdk['dart']),
      ('flutter', sdk['flutter'], other.sdk['flutter']),
    ]) {
      if (a != b) lines.add('$name version differs: $a vs $b');
    }
    if (pricingVersion != other.pricingVersion) {
      lines.add('pricing differs: $pricingVersion vs ${other.pricingVersion}');
    }
    return lines;
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final left = [...a]..sort();
    final right = [...b]..sort();
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
