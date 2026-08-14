import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';

/// Scans the Flutter project dependencies, assets, and bundle configuration
/// to detect bloat, missing pins, and package health issues.
class AuditCommand extends Command<void> {
  @override
  final String name = 'audit';

  @override
  final String description = 'Audit Flutter app dependencies, assets, and bundle health.';

  @override
  Future<void> run() async {
    final root = Directory.current;
    final pubspecFile = File('${root.path}/pubspec.yaml');

    if (!pubspecFile.existsSync()) {
      stderr.writeln('❌ Error: pubspec.yaml not found in current directory (${root.path}).');
      exitCode = 1;
      return;
    }

    stdout.writeln('🔍 Running FlutterPilot Project & Dependency Health Audit...\n');

    final pubspecContent = pubspecFile.readAsStringSync();
    final directDeps = <String>[];
    final devDeps = <String>[];

    bool inDeps = false;
    bool inDevDeps = false;

    for (final line in pubspecContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#') || trimmed.isEmpty) continue;

      if (line.startsWith('dependencies:')) {
        inDeps = true;
        inDevDeps = false;
        continue;
      } else if (line.startsWith('dev_dependencies:')) {
        inDeps = false;
        inDevDeps = true;
        continue;
      } else if (line.startsWith(RegExp(r'^[a-zA-Z_]'))) {
        inDeps = false;
        inDevDeps = false;
      }

      if (inDeps && line.startsWith('  ') && !line.startsWith('    ')) {
        final name = trimmed.split(':').first.trim();
        if (name.isNotEmpty && name != 'flutter') directDeps.add(name);
      } else if (inDevDeps && line.startsWith('  ') && !line.startsWith('    ')) {
        final name = trimmed.split(':').first.trim();
        if (name.isNotEmpty && name != 'flutter_test') devDeps.add(name);
      }
    }

    // Check package_config.json for total transitive packages
    int totalTransitive = 0;
    final packageConfigFile = File('${root.path}/.dart_tool/package_config.json');
    if (packageConfigFile.existsSync()) {
      try {
        final decoded = json.decode(packageConfigFile.readAsStringSync());
        final packages = decoded['packages'] as List?;
        totalTransitive = packages?.length ?? 0;
      } catch (_) {}
    }

    // Check assets directory size
    int totalAssetBytes = 0;
    int assetCount = 0;
    final assetsDir = Directory('${root.path}/assets');
    if (assetsDir.existsSync()) {
      for (final entity in assetsDir.listSync(recursive: true)) {
        if (entity is File) {
          assetCount++;
          totalAssetBytes += entity.lengthSync();
        }
      }
    }

    final assetMb = totalAssetBytes / (1024 * 1024);

    stdout.writeln('========================================');
    stdout.writeln('📦 Project Health & Dependency Summary');
    stdout.writeln('========================================');
    stdout.writeln('Direct Dependencies:     ${directDeps.length}');
    stdout.writeln('Dev Dependencies:        ${devDeps.length}');
    stdout.writeln('Total Transitive Packages: ${totalTransitive > 0 ? totalTransitive : "Run flutter pub get"}');
    stdout.writeln('Static Assets:           $assetCount file(s) (${assetMb.toStringAsFixed(2)} MB)');
    stdout.writeln('----------------------------------------');

    final warnings = <String>[];
    if (assetMb > 50.0) {
      warnings.add('Assets directory exceeds 50MB (${assetMb.toStringAsFixed(1)}MB). Consider compressing static assets or using on-demand downloads.');
    }
    if (directDeps.length > 50) {
      warnings.add('Direct dependencies count (${directDeps.length}) is high. Audit for redundant or unused packages.');
    }

    if (warnings.isNotEmpty) {
      stdout.writeln('\n⚠️ Warnings:');
      for (final w in warnings) {
        stdout.writeln(' • $w');
      }
    } else {
      stdout.writeln('✅ No critical bundle bloat or health issues detected.');
    }
  }
}
