import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// Migrates a Flutter project from legacy `flutterpilot_*` naming to `fp_*`.
///
/// Updates:
/// - `pubspec.yaml` dependencies and dev_dependencies
/// - Dart imports (`package:flutterpilot_*` -> `package:fp_*`)
/// - MCP configuration files (`.mcp.json`, `opencode.json`, `.vscode/settings.json`, etc.)
/// - Tool and CI scripts
class MigrateCommand extends Command<void> {
  MigrateCommand() {
    argParser
      ..addOption(
        'project',
        abbr: 'p',
        defaultsTo: '.',
        help: 'Path to Flutter project root (default: current directory).',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: false,
        help: 'Print planned migrations without writing changes to disk.',
      );
  }

  @override
  final String name = 'migrate';

  @override
  final String description =
      'Migrate a project from legacy flutterpilot_* packages and imports to fp_*.';

  static const Map<String, String> packageMap = {
    'flutterpilot_sdk': 'fp_sdk',
    'flutterpilot_riverpod': 'fp_riverpod',
    'flutterpilot_supabase': 'fp_supabase',
    'flutterpilot_drift': 'fp_drift',
    'flutterpilot_gorouter': 'fp_gorouter',
    'flutterpilot_shared_preferences': 'fp_shared_preferences',
    'flutterpilot_connectivity': 'fp_connectivity',
    'flutterpilot_bloc': 'fp_bloc',
    'flutterpilot_dio': 'fp_dio',
    'flutterpilot_firebase': 'fp_firebase',
    'flutterpilot_hive': 'fp_hive',
    'flutterpilot_sqlite': 'fp_sqlite',
    'flutterpilot_sqflite': 'fp_sqflite',
    'flutterpilot_secure_storage': 'fp_secure_storage',
    'flutterpilot_cli': 'fp_cli',
    'flutterpilot_server': 'fp_server',
  };

  @override
  Future<void> run() async {
    final project = p.normalize(p.absolute(argResults!['project'] as String));
    final dryRun = argResults!['dry-run'] as bool;

    stdout.writeln(
      '🚀 ${dryRun ? 'Checking migration' : 'Migrating'} for project at $project...\n',
    );

    final pubspecFile = File(p.join(project, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      stderr.writeln('❌ Error: pubspec.yaml not found at ${pubspecFile.path}');
      exitCode = 1;
      return;
    }

    var filesModified = 0;
    var totalReplacements = 0;

    // 1. Migrate pubspec.yaml
    final pubspecResult = _migratePubspec(pubspecFile, dryRun);
    if (pubspecResult.replacements > 0) {
      filesModified++;
      totalReplacements += pubspecResult.replacements;
      stdout.writeln(
        '  ${dryRun ? '[dry-run] Would update' : '✓ Updated'} pubspec.yaml (${pubspecResult.replacements} package references)',
      );
    }

    // 2. Migrate Dart source files
    final searchDirs = ['lib', 'tool', 'test', 'test_driver', 'bin'];
    for (final dirName in searchDirs) {
      final dir = Directory(p.join(project, dirName));
      if (!dir.existsSync()) continue;

      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final res = _migrateDartFile(entity, dryRun);
        if (res.replacements > 0) {
          filesModified++;
          totalReplacements += res.replacements;
          final relPath = p.relative(entity.path, from: project);
          stdout.writeln(
            '  ${dryRun ? '[dry-run] Would update' : '✓ Updated'} $relPath (${res.replacements} imports)',
          );
        }
      }
    }

    // 3. Migrate MCP config files
    final mcpConfigs = [
      '.mcp.json',
      'opencode.json',
      p.join('.vscode', 'settings.json'),
      p.join('.cursor', 'mcp.json'),
    ];
    for (final configPath in mcpConfigs) {
      final configFile = File(p.join(project, configPath));
      if (!configFile.existsSync()) continue;
      final res = _migrateConfigFile(configFile, dryRun);
      if (res.replacements > 0) {
        filesModified++;
        totalReplacements += res.replacements;
        stdout.writeln(
          '  ${dryRun ? '[dry-run] Would update' : '✓ Updated'} $configPath (${res.replacements} occurrences)',
        );
      }
    }

    // 4. Migrate scripts folder if present
    final scriptsDir = Directory(p.join(project, 'scripts'));
    if (scriptsDir.existsSync()) {
      for (final entity in scriptsDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.sh') || entity.path.endsWith('.bash')) {
          final res = _migrateConfigFile(entity, dryRun);
          if (res.replacements > 0) {
            filesModified++;
            totalReplacements += res.replacements;
            final relPath = p.relative(entity.path, from: project);
            stdout.writeln(
              '  ${dryRun ? '[dry-run] Would update' : '✓ Updated'} $relPath (${res.replacements} occurrences)',
            );
          }
        }
      }
    }

    stdout.writeln('\n========================================');
    if (filesModified == 0) {
      stdout.writeln('✨ Project is already fully migrated to fp_*! No changes needed.');
    } else {
      stdout.writeln(
        '🎉 ${dryRun ? 'Planned' : 'Completed'} migration across $filesModified file(s) with $totalReplacements replacement(s).',
      );
      if (!dryRun) {
        stdout.writeln('\nNext step: run `flutter pub get` to update dependencies.');
      }
    }
  }

  static ({int replacements}) _migratePubspec(File file, bool dryRun) {
    final original = file.readAsStringSync();
    var content = original;
    var count = 0;

    for (final entry in packageMap.entries) {
      // Matches: "  flutterpilot_sdk:" or "flutterpilot_sdk:"
      final depPattern = RegExp('^([ \\t]*)${entry.key}:', multiLine: true);
      if (depPattern.hasMatch(content)) {
        content = content.replaceAllMapped(depPattern, (match) {
          count++;
          return '${match.group(1)}${entry.value}:';
        });
      }
      // Matches path dependencies targeting package folders: path: .../flutterpilot_sdk
      final pathPattern = RegExp('/${entry.key}([\'"\\s]|\\\$)');
      if (pathPattern.hasMatch(content)) {
        content = content.replaceAllMapped(pathPattern, (match) {
          count++;
          return '/${entry.value}${match.group(1)}';
        });
      }
    }

    if (count > 0 && !dryRun) {
      file.writeAsStringSync(content);
    }
    return (replacements: count);
  }

  static ({int replacements}) _migrateDartFile(File file, bool dryRun) {
    final original = file.readAsStringSync();
    var content = original;
    var count = 0;

    for (final entry in packageMap.entries) {
      final canonicalImport = "package:${entry.key}/${entry.key}.dart";
      if (content.contains(canonicalImport)) {
        final matches = canonicalImport.allMatches(content).length;
        count += matches;
        content = content.replaceAll(
          canonicalImport,
          "package:${entry.value}/${entry.value}.dart",
        );
      }
      final importPattern = "package:${entry.key}/";
      if (content.contains(importPattern)) {
        final matches = importPattern.allMatches(content).length;
        count += matches;
        content = content.replaceAll(importPattern, "package:${entry.value}/");
      }
    }

    if (count > 0 && !dryRun) {
      file.writeAsStringSync(content);
    }
    return (replacements: count);
  }

  static ({int replacements}) _migrateConfigFile(File file, bool dryRun) {
    final original = file.readAsStringSync();
    var content = original;
    var count = 0;

    for (final entry in packageMap.entries) {
      if (content.contains(entry.key)) {
        final matches = entry.key.allMatches(content).length;
        count += matches;
        content = content.replaceAll(entry.key, entry.value);
      }
    }

    if (count > 0 && !dryRun) {
      file.writeAsStringSync(content);
    }
    return (replacements: count);
  }
}
