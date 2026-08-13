import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Command to initialize FlutterPilot in an existing Flutter project.
class InitCommand extends Command<void> {
  @override
  final String name = 'init';

  @override
  final String description =
      'Initializes FlutterPilot SDK and detected plugins in the current Flutter app.';

  InitCommand() {
    argParser.addOption(
      'project-root',
      abbr: 'p',
      help: 'Path to Flutter project root (where pubspec.yaml lives).',
      defaultsTo: '.',
    );
  }

  @override
  Future<void> run() async {
    final rootPath = argResults?['project-root'] as String? ?? '.';
    final projectDir = Directory(rootPath);

    if (!projectDir.existsSync()) {
      stderr.writeln('❌ Error: Directory "$rootPath" does not exist.');
      exit(1);
    }

    final pubspecFile = File(p.join(projectDir.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      stderr.writeln(
        '❌ Error: No pubspec.yaml found in ${projectDir.path}. Are you in a Flutter project?',
      );
      exit(1);
    }

    stdout.writeln('🔍 Analyzing Flutter project dependencies...');
    final pubspecContent = await pubspecFile.readAsString();
    final dynamic yaml = loadYaml(pubspecContent);

    final dependencies = yaml['dependencies'] as Map? ?? {};
    final devDependencies = yaml['dev_dependencies'] as Map? ?? {};

    final pluginsToAdd = <String>[];
    final detected = <String>[];

    // Helper map of app dependencies to matching FlutterPilot plugins
    final pluginMap = {
      'flutter_riverpod': 'flutterpilot_riverpod',
      'riverpod': 'flutterpilot_riverpod',
      'flutter_bloc': 'flutterpilot_bloc',
      'bloc': 'flutterpilot_bloc',
      'dio': 'flutterpilot_dio',
      'drift': 'flutterpilot_drift',
      'hive': 'flutterpilot_hive',
      'hive_flutter': 'flutterpilot_hive',
      'shared_preferences': 'flutterpilot_shared_preferences',
      'go_router': 'flutterpilot_gorouter',
      'supabase_flutter': 'flutterpilot_supabase',
      'firebase_core': 'flutterpilot_firebase',
      'flutter_secure_storage': 'flutterpilot_secure_storage',
      'connectivity_plus': 'flutterpilot_connectivity',
      'sqflite': 'flutterpilot_sqflite',
    };

    for (final entry in pluginMap.entries) {
      if (dependencies.containsKey(entry.key)) {
        detected.add(entry.key);
        if (!pluginsToAdd.contains(entry.value)) {
          pluginsToAdd.add(entry.value);
        }
      }
    }

    stdout.writeln('📦 Detected state & framework packages: ${detected.isEmpty ? "Standard Flutter" : detected.join(", ")}');
    stdout.writeln('🚀 Adding flutterpilot_sdk and plugins: ${pluginsToAdd.join(", ")}');

    // Update pubspec.yaml using YamlEditor
    final editor = YamlEditor(pubspecContent);
    if (!devDependencies.containsKey('flutterpilot_sdk')) {
      if (!yaml.containsKey('dev_dependencies') || yaml['dev_dependencies'] == null) {
        editor.update(['dev_dependencies'], {'flutterpilot_sdk': '^0.1.0'});
      } else {
        editor.update(['dev_dependencies', 'flutterpilot_sdk'], '^0.1.0');
      }
    }

    for (final plugin in pluginsToAdd) {
      if (!devDependencies.containsKey(plugin)) {
        editor.update(['dev_dependencies', plugin], '^0.1.0');
      }
    }

    await pubspecFile.writeAsString(editor.toString());
    stdout.writeln('✅ Updated pubspec.yaml with FlutterPilot packages.');

    // Safely patch lib/main.dart
    final mainFile = File(p.join(projectDir.path, 'lib', 'main.dart'));
    if (mainFile.existsSync()) {
      var mainContent = await mainFile.readAsString();
      if (!mainContent.contains('FlutterPilot.initialize')) {
        // Add import
        if (!mainContent.contains("package:flutterpilot_sdk/flutterpilot_sdk.dart")) {
          mainContent = "import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';\n$mainContent";
        }

        // Insert FlutterPilot.initialize() inside main()
        final mainRegex = RegExp(r'(void\s+main\s*\([^)]*\)\s*(?:async)?\s*\{)');
        if (mainRegex.hasMatch(mainContent)) {
          mainContent = mainContent.replaceFirstMapped(mainRegex, (match) {
            return '${match.group(1)}\n  WidgetsFlutterBinding.ensureInitialized();\n  FlutterPilot.initialize();';
          });
          await mainFile.writeAsString(mainContent);
          stdout.writeln('✅ Injected FlutterPilot.initialize() into lib/main.dart.');
        } else {
          stdout.writeln('⚠️ Note: Could not auto-patch main() in lib/main.dart. Please add `FlutterPilot.initialize();` manually.');
        }
      } else {
        stdout.writeln('ℹ️ FlutterPilot is already initialized in lib/main.dart.');
      }
    }

    stdout.writeln('\n🎉 FlutterPilot initialized successfully!');
    stdout.writeln('Next steps:');
    stdout.writeln('  1. Run `flutter pub get`');
    stdout.writeln('  2. Run `flutter run`');
    stdout.writeln('  3. Start your AI Agent in Cursor / Claude Code — your app is now AI-native!\n');
  }
}
