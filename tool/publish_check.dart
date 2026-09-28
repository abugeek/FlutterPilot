import 'dart:io';

/// Runs `pub publish --dry-run` for every package, in the order they must
/// be published (SDK, plugins, server, CLI), and fails on any warning or
/// error. Nothing is published.
///
/// Plugins depend on the hosted flutterpilot_sdk, which pub.dev doesn't
/// have until the SDK is published: a package without its own
/// pubspec_overrides.yaml gets a temporary one pointing at the checkout's
/// SDK (pub then prints a hint about it, which is expected).
///
/// Usage (from the repo root): dart run tool/publish_check.dart
Future<void> main() async {
  final plugins =
      Directory('packages/plugins')
          .listSync()
          .whereType<Directory>()
          .where((d) => File('${d.path}/pubspec.yaml').existsSync())
          .map((d) => d.path)
          .toList()
        ..sort();
  final packages = [
    'packages/flutterpilot_sdk',
    ...plugins,
    'packages/flutterpilot_server',
    'packages/flutterpilot_cli',
  ];

  final problems = <String>[];
  for (final dir in packages) {
    final name = dir.split('/').last;
    final pubspec = File('$dir/pubspec.yaml').readAsStringSync();
    final overrides = File('$dir/pubspec_overrides.yaml');
    final temporary =
        !overrides.existsSync() &&
        RegExp(r'^\s+flutterpilot_sdk:', multiLine: true).hasMatch(pubspec);
    if (temporary) {
      overrides.writeAsStringSync(
        'dependency_overrides:\n'
        '  flutterpilot_sdk:\n'
        '    path: ${'../' * dir.split('/').length}'
        'packages/flutterpilot_sdk\n',
      );
    }
    try {
      final flutter = RegExp(r'sdk:\s*flutter').hasMatch(pubspec);
      final r = await Process.run(flutter ? 'flutter' : 'dart', [
        'pub',
        'publish',
        '--dry-run',
      ], workingDirectory: dir);
      final out = '${r.stdout}${r.stderr}';
      final summary = RegExp(r'Package has (\d+) warnings?').firstMatch(out);
      final warnings = int.tryParse(summary?[1] ?? '') ?? -1;
      if (r.exitCode != 0 || warnings != 0) {
        final details = out
            .split('\n')
            .skipWhile((l) => !l.startsWith('Package validation'))
            .take(20)
            .join('\n');
        problems.add(
          '$name (exit ${r.exitCode}):\n'
          '${details.isEmpty ? out.split('\n').take(10).join('\n') : details}',
        );
        stdout.writeln('❌ $name');
      } else {
        stdout.writeln('✅ $name');
      }
    } finally {
      if (temporary) overrides.deleteSync();
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln('\n${problems.join('\n\n')}');
    exit(1);
  }
  stdout.writeln('\nAll ${packages.length} packages are ready to publish.');
}
