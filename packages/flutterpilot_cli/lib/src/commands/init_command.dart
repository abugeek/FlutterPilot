import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

const _repoUrl = 'https://github.com/abugeek/FlutterPilot.git';

/// App dependency -> (FlutterPilot plugin, wiring line the user must add).
const _plugins = {
  'flutter_riverpod': (
    'flutterpilot_riverpod',
    'ProviderScope(observers: [RiverpodPilotObserver()], child: ...)',
  ),
  'riverpod': (
    'flutterpilot_riverpod',
    'ProviderScope(observers: [RiverpodPilotObserver()], child: ...)',
  ),
  'flutter_bloc': ('flutterpilot_bloc', 'Bloc.observer = BlocPilotObserver();'),
  'bloc': ('flutterpilot_bloc', 'Bloc.observer = BlocPilotObserver();'),
  'dio': (
    'flutterpilot_dio',
    'DioPilotInterceptor.register();  // in main(), so its tools are listed '
        'before the first request; and dio.interceptors.add('
        'DioPilotInterceptor()) on every Dio you create',
  ),
  'drift': (
    'flutterpilot_drift',
    "DriftPilotInspector.registerDatabase('main', db);",
  ),
  'hive': ('flutterpilot_hive', 'HivePilotInspector.registerBox(box);'),
  'hive_flutter': ('flutterpilot_hive', 'HivePilotInspector.registerBox(box);'),
  'hive_ce': ('flutterpilot_hive', 'HivePilotInspector.registerBox(box);'),
  'hive_ce_flutter': (
    'flutterpilot_hive',
    'HivePilotInspector.registerBox(box);',
  ),
  'shared_preferences': (
    'flutterpilot_shared_preferences',
    'SharedPrefsPilotInspector.register(await SharedPreferences.getInstance());',
  ),
  'go_router': (
    'flutterpilot_gorouter',
    'GoRouterPilotInspector.register(router);',
  ),
  'supabase_flutter': (
    'flutterpilot_supabase',
    'SupabasePilotInspector.register(Supabase.instance.client);',
  ),
  // Not firebase_core: the plugin brings Auth + Firestore, which an app
  // using only e.g. Analytics shouldn't get.
  'firebase_auth': (
    'flutterpilot_firebase',
    'FirebasePilotInspector.register(auth: FirebaseAuth.instance, '
        'firestore: FirebaseFirestore.instance);',
  ),
  'cloud_firestore': (
    'flutterpilot_firebase',
    'FirebasePilotInspector.register(auth: FirebaseAuth.instance, '
        'firestore: FirebaseFirestore.instance);',
  ),
  'flutter_secure_storage': (
    'flutterpilot_secure_storage',
    'SecureStoragePilotInspector.register(storage);',
  ),
  'connectivity_plus': (
    'flutterpilot_connectivity',
    'ConnectivityPilotInspector.register();',
  ),
  'sqflite': (
    'flutterpilot_sqflite',
    "SqflitePilotInspector.registerDatabase('main', db);",
  ),
};

/// Command to initialize FlutterPilot in an existing Flutter project.
class InitCommand extends Command<void> {
  @override
  final String name = 'init';

  @override
  final String description =
      'Initializes FlutterPilot SDK and detected plugins in the current Flutter app.';

  InitCommand() {
    argParser
      ..addOption(
        'project-root',
        abbr: 'p',
        help: 'Path to Flutter project root (where pubspec.yaml lives).',
        defaultsTo: '.',
      )
      ..addOption(
        'local',
        help:
            'Path to a local FlutterPilot checkout. Uses path dependencies '
            'instead of git (for testing unpushed changes).',
      )
      ..addOption(
        'ref',
        help: 'Git ref (branch, tag, or commit) to pin when using git.',
        defaultsTo: 'main',
      );
  }

  @override
  Future<void> run() async {
    final rootPath = argResults?['project-root'] as String? ?? '.';
    final local = argResults?['local'] as String?;
    final ref = argResults?['ref'] as String? ?? 'main';

    final pubspecFile = File(p.join(rootPath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw UsageException(
        'No pubspec.yaml found in ${p.absolute(rootPath)}. Are you in a Flutter project?',
        usage,
      );
    }
    if (local != null &&
        !File(
          p.join(local, 'packages', 'flutterpilot_sdk', 'pubspec.yaml'),
        ).existsSync()) {
      throw UsageException(
        '--local "$local" is not a FlutterPilot checkout.',
        usage,
      );
    }

    // Packages are not on pub.dev yet: point at git, or a local checkout.
    Object source(String package) {
      final subdir = package == 'flutterpilot_sdk'
          ? 'packages/$package'
          : 'packages/plugins/$package';
      if (local != null) {
        return {
          'path': p.relative(
            p.absolute(local, subdir),
            from: p.absolute(rootPath),
          ),
        };
      }
      return {
        'git': {'url': _repoUrl, 'path': subdir, 'ref': ref},
      };
    }

    final pubspecContent = await pubspecFile.readAsString();
    final yaml = loadYaml(pubspecContent) as YamlMap;
    final dependencies = (yaml['dependencies'] as Map?) ?? const {};

    final detected = <String, (String, String)>{
      for (final e in _plugins.entries)
        if (dependencies.containsKey(e.key)) e.value.$1: e.value,
    };

    stdout.writeln(
      '📦 Detected: ${detected.isEmpty ? "no supported packages" : detected.keys.join(", ")}',
    );

    // Regular dependencies (not dev_dependencies): lib/main.dart imports them.
    // FlutterPilot.initialize() is a no-op in release builds.
    final editor = YamlEditor(pubspecContent);
    for (final package in ['flutterpilot_sdk', ...detected.keys]) {
      editor.update(['dependencies', package], source(package));
    }
    // Plugins depend on hosted flutterpilot_sdk; force them onto the same source.
    if (detected.isNotEmpty) {
      if (yaml['dependency_overrides'] == null) {
        editor.update(
          ['dependency_overrides'],
          {'flutterpilot_sdk': source('flutterpilot_sdk')},
        );
      } else {
        editor.update([
          'dependency_overrides',
          'flutterpilot_sdk',
        ], source('flutterpilot_sdk'));
      }
    }
    await pubspecFile.writeAsString(editor.toString());
    stdout.writeln('✅ Updated pubspec.yaml.');

    final mainFile = File(p.join(rootPath, 'lib', 'main.dart'));
    var trackerAdded = false;
    final trackedBefore =
        mainFile.existsSync() &&
        mainFile.readAsStringSync().contains('NavigationTracker');
    if (mainFile.existsSync()) {
      final content = await mainFile.readAsString();
      final patched = patchMain(content);
      if (patched == content) {
        stdout.writeln(
          'ℹ️ lib/main.dart already calls FlutterPilot.initialize().',
        );
      } else if (patched == null) {
        stdout.writeln(
          '⚠️ Could not find main() in lib/main.dart. Add `FlutterPilot.initialize();` at its start manually.',
        );
      } else {
        await mainFile.writeAsString(patched);
        stdout.writeln('✅ Added FlutterPilot.initialize() to lib/main.dart.');
      }
    }

    if (mainFile.existsSync()) {
      final content = await mainFile.readAsString();
      final withTracker = addNavigationTracker(content);
      if (withTracker != content) {
        await mainFile.writeAsString(withTracker);
        trackerAdded = true;
        stdout.writeln(
          '✅ Added NavigationTracker() to MaterialApp navigatorObservers.',
        );
      }
    }

    if (mainFile.existsSync()) {
      final content = await mainFile.readAsString();
      final withImport = ensureImport(content);
      if (withImport != content) await mainFile.writeAsString(withImport);
    }

    stdout.writeln('\nNext steps:');
    stdout.writeln('  1. flutter pub get');
    stdout.writeln(
      routeTrackingStep(
        mainFile.existsSync() ? mainFile.readAsStringSync() : '',
        trackerAdded: trackerAdded,
        trackedBefore: trackedBefore,
        goRouter: detected.containsKey('flutterpilot_gorouter'),
      ),
    );
    if (detected.isNotEmpty) {
      stdout.writeln(
        '  3. Wire each plugin (import package:<plugin>/<plugin>.dart) — they do nothing until you do:',
      );
      for (final MapEntry(key: plugin, value: (_, line)) in detected.entries) {
        stdout.writeln('       $plugin:  $line');
      }
    }
    stdout.writeln(
      '  ${detected.isEmpty ? 3 : 4}. flutterpilot mcp install (connects Claude Code / '
      'Cursor / VS Code), then flutterpilot dev (runs the app so the server finds it).',
    );
  }

  /// Next step 2: what init did about route tracking, and what's left.
  /// Without any tracking, the SDK names routes after the on-screen page.
  static String routeTrackingStep(
    String main, {
    required bool trackerAdded,
    required bool trackedBefore,
    required bool goRouter,
  }) {
    if (goRouter) {
      return '  2. Route tracking (go_router): wire flutterpilot_gorouter '
          '(step 3) for full locations like /story/42; until then routes are '
          "named after the on-screen page's path pattern.";
    }
    if (trackerAdded) {
      return '  2. Route tracking: added NavigationTracker() to MaterialApp.';
    }
    if (trackedBefore) {
      return '  2. Route tracking: already wired (NavigationTracker).';
    }
    if (RegExp(r'App\.router\s*\(').hasMatch(main)) {
      return "  2. Route tracking: MaterialApp.router can't take "
          "NavigationTracker; routes are named after the on-screen page's "
          "name. Your router's FlutterPilot plugin gives full locations.";
    }
    return '  2. Add `navigatorObservers: [NavigationTracker()]` to your '
        'MaterialApp (not found in lib/main.dart). Until then routes are '
        "named after the on-screen page's name.";
  }

  /// Adds `NavigationTracker()` to a plain `MaterialApp(` (not `.router`),
  /// dropping a leading `const`, which the non-const observer would break.
  static String addNavigationTracker(String content) {
    if (content.contains('NavigationTracker')) return content;
    final app = RegExp(r'(?:const\s+)?MaterialApp\s*\(');
    final match = app.firstMatch(content);
    if (match == null) return content;
    final observers = RegExp(r'navigatorObservers:\s*\[');
    final obs = observers.firstMatch(content.substring(match.end));
    if (obs != null) {
      final at = match.end + obs.end;
      return content.replaceRange(
        match.start,
        at,
        '${content.substring(match.start, at).replaceFirst(RegExp(r'^const\s+'), '')}NavigationTracker(), ',
      );
    }
    return content.replaceRange(
      match.start,
      match.end,
      'MaterialApp(\n      navigatorObservers: [NavigationTracker()],',
    );
  }

  /// Returns [content] with the import and `FlutterPilot.initialize()` added,
  /// the unchanged [content] if already initialized, or null if no main() found.
  static String? patchMain(String content) {
    if (content.contains('FlutterPilot.initialize')) return content;
    // Reuse the app's own binding call instead of adding a second one.
    const binding = 'WidgetsFlutterBinding.ensureInitialized();';
    if (content.contains(binding)) {
      return content.replaceFirst(
        binding,
        '$binding\n  FlutterPilot.initialize();',
      );
    }
    const init =
        '\n  WidgetsFlutterBinding.ensureInitialized();\n  FlutterPilot.initialize();';
    final blockMain = RegExp(
      r'((?:Future<void>|void)\s+main\s*\([^)]*\)\s*(?:async\s*)?\{)',
    );
    if (blockMain.hasMatch(content)) {
      return content.replaceFirstMapped(blockMain, (m) => '${m[1]}$init');
    }
    // `void main() => runApp(...);`
    final arrowMain = RegExp(
      r'((?:Future<void>|void)\s+main\s*\([^)]*\)\s*(?:async\s*)?)=>\s*([^;]+);',
    );
    if (arrowMain.hasMatch(content)) {
      return content.replaceFirstMapped(
        arrowMain,
        (m) => '${m[1]}{$init\n  ${m[2]!.trim()};\n}',
      );
    }
    return null;
  }

  /// Every injected snippet references the SDK; make sure it's imported.
  static String ensureImport(String content) {
    const import = "import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';";
    if (content.contains(import)) return content;
    if (!content.contains('FlutterPilot') &&
        !content.contains('NavigationTracker')) {
      return content;
    }
    return '$import\n$content';
  }
}
