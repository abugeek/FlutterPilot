import 'dart:convert';
import 'dart:io';

/// Fails when a plugin's version constraint keeps an app on the latest
/// release of the host package (go_router, flutter_bloc, ...) from installing
/// the plugin. This happened twice (flutter_bloc ^8, go_router <16).
///
/// For every direct dependency of every plugin it compares `upgradable`
/// (newest version our constraint allows) with `resolvable` (newest version
/// the rest of the graph and the Flutter SDK allow). If they differ, our
/// constraint is the only thing in the way.
///
/// Usage (from the repo root, after `melos bootstrap`):
///   dart run tool/check_plugin_ranges.dart
Future<void> main() async {
  final plugins =
      Directory('packages/plugins')
          .listSync()
          .whereType<Directory>()
          .where((d) => File('${d.path}/pubspec.yaml').existsSync())
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final problems = <String>[];
  for (final plugin in plugins) {
    final name = plugin.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final r = await Process.run(
      'flutter',
      ['pub', 'outdated', '--json'],
      workingDirectory: plugin.path,
      runInShell: true,
    );
    if (r.exitCode != 0) {
      problems.add('$name: `flutter pub outdated` failed:\n${r.stderr}');
      continue;
    }
    final packages = (jsonDecode(r.stdout as String)['packages'] as List)
        .cast<Map<String, dynamic>>();
    for (final p in packages.where((p) => p['kind'] == 'direct')) {
      final allowed = (p['upgradable'] as Map?)?['version'];
      final possible = (p['resolvable'] as Map?)?['version'];
      if (possible != null && allowed != possible) {
        problems.add(
          '$name: constraint on ${p['package']} allows up to $allowed, '
          'but $possible is out — raise the upper bound to the next major.',
        );
      }
    }
    stdout.writeln('checked $name');
  }

  if (problems.isEmpty) {
    stdout.writeln('All plugin ranges accept the latest host packages.');
    return;
  }
  stderr.writeln(problems.join('\n'));
  exitCode = 1;
}
