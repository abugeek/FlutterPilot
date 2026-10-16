// Read-only fixture preflight (task 00 §10). Reports every missing or
// revision-mismatched input for the agent evals before anything launches.
//
//   cd packages/fp_server
//   dart run tool/eval/check_fixtures.dart
//   dart run tool/eval/check_fixtures.dart --fixtures D:/projects/flutter
//   dart run tool/eval/check_fixtures.dart --require-clean   # baseline-grade
//
// Exit 0 when nothing is blocking; 1 when any input is missing or mismatched;
// 2 when the manifest itself is malformed or missing.
import 'dart:io';

import 'package:args/args.dart';

import 'src/fixtures.dart';

/// The manifest path (`tool/eval/fixtures/manifest.json`, next to this script).
File manifestFile() {
  final evalDir = File.fromUri(Platform.script).parent;
  return File(
    '${evalDir.path}${Platform.pathSeparator}fixtures'
    '${Platform.pathSeparator}manifest.json',
  );
}

/// The default fixtures root: the repository's parent directory, where the
/// sibling lab apps live. Found by walking up from this script to `.git`.
String defaultFixturesRoot() {
  var dir = File.fromUri(Platform.script).parent;
  while (true) {
    if (Directory('${dir.path}${Platform.pathSeparator}.git').existsSync() ||
        File('${dir.path}${Platform.pathSeparator}.git').existsSync()) {
      return dir.parent.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return dir.path;
    dir = parent;
  }
}

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption(
      'fixtures',
      help:
          'Directory holding one subdirectory per fixture id '
          '(default: the repository\'s parent).',
    )
    ..addFlag(
      'require-clean',
      negatable: false,
      help: 'Treat a dirty fixture checkout as blocking (baseline runs).',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');
  final args = parser.parse(argv);
  if (args['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  final FixtureManifest manifest;
  try {
    manifest = FixtureManifest.load(manifestFile());
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
    return;
  }

  final root = (args['fixtures'] as String?) ?? defaultFixturesRoot();
  stdout.writeln('Fixture preflight');
  stdout.writeln('manifest: ${manifestFile().path}');
  stdout.writeln('fixtures: $root');
  stdout.writeln('${manifest.fixtures.length} fixtures declared');
  stdout.writeln();

  final issues = preflightFixtures(
    manifest,
    fixturesRoot: root,
    requireClean: args['require-clean'] as bool,
  );
  if (issues.isEmpty) {
    stdout.writeln('All fixtures match the manifest.');
    return;
  }
  for (final issue in issues) {
    stdout.writeln(issue);
  }
  final blocking = issues
      .where((i) => i.level == FixtureIssueLevel.blocking)
      .length;
  stdout.writeln();
  stdout.writeln('$blocking blocking, ${issues.length - blocking} warning(s).');
  if (blocking > 0) exitCode = 1;
}
