import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../version.dart';

const _repoUrl = 'https://github.com/abugeek/FlutterPilot.git';

/// App dependency -> (FlutterPilot plugin, wiring line the user must add).
/// Shared by `init` (adds the plugin) and `doctor` (checks it is wired).
const appPlugins = {
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

/// The class a plugin's wiring line uses (`DioPilotInterceptor`): once it
/// appears in the app's code, the plugin is wired.
String? wiringSymbol(String wiring) =>
    RegExp(r'\b[A-Z]\w*Pilot\w*\b').firstMatch(wiring)?[0];

/// All of the app's own Dart code (lib/), concatenated.
String appSources(String project) {
  final lib = Directory(p.join(project, 'lib'));
  if (!lib.existsSync()) return '';
  final buffer = StringBuffer();
  for (final f in lib.listSync(recursive: true)) {
    if (f is File && f.path.endsWith('.dart')) {
      try {
        buffer.writeln(f.readAsStringSync());
      } catch (_) {}
    }
  }
  return buffer.toString();
}

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
      )
      ..addOption(
        'source',
        allowed: ['auto', 'hosted', 'git'],
        defaultsTo: 'auto',
        help:
            'Where the packages come from. auto: pub.dev once FlutterPilot '
            'is published there (this release, ^$flutterpilotVersion), else '
            'git. --ref implies git, --local a path.',
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

    final hosted =
        local == null &&
        switch (argResults?['source'] as String? ?? 'auto') {
          'hosted' => true,
          'git' => false,
          _ => !(argResults?.wasParsed('ref') ?? false) && await onPubDev(),
        };
    stdout.writeln(
      local != null
          ? '📦 Using the FlutterPilot checkout at $local.'
          : hosted
          ? '📦 Using pub.dev (FlutterPilot ^$flutterpilotVersion).'
          : '📦 Using git ($ref): FlutterPilot is not on pub.dev yet '
                '(--source hosted to force it).',
    );

    // A local checkout, this release from pub.dev, or git.
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
      if (hosted) return '^$flutterpilotVersion';
      return {
        'git': {'url': _repoUrl, 'path': subdir, 'ref': ref},
      };
    }

    final pubspecContent = await pubspecFile.readAsString();
    final yaml = loadYaml(pubspecContent) as YamlMap;
    final dependencies = (yaml['dependencies'] as Map?) ?? const {};

    final detected = <String, (String, String)>{
      for (final e in appPlugins.entries)
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
    // Plugins depend on hosted flutterpilot_sdk; from git or a checkout,
    // force them onto the same source. From pub.dev they already are: drop
    // an override an earlier git init left.
    final overrides = yaml['dependency_overrides'];
    if (hosted) {
      if (overrides is Map && overrides.containsKey('flutterpilot_sdk')) {
        if (overrides.length == 1) {
          editor.remove(['dependency_overrides']);
        } else {
          editor.remove(['dependency_overrides', 'flutterpilot_sdk']);
        }
      }
    } else if (detected.isNotEmpty) {
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
    if (editor.toString() == pubspecContent) {
      stdout.writeln('ℹ️ pubspec.yaml already has FlutterPilot.');
    } else {
      await pubspecFile.writeAsString(editor.toString());
      stdout.writeln('✅ Updated pubspec.yaml.');
    }

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

    for (final line in addMacosNetworkClient(rootPath)) {
      stdout.writeln(line);
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
    // Only the plugins the app doesn't use yet (a re-run lists none).
    final sources = appSources(rootPath);
    final unwired = {
      for (final MapEntry(key: plugin, value: (_, line)) in detected.entries)
        if (!sources.contains(wiringSymbol(line) ?? line)) plugin: line,
    };
    if (unwired.isNotEmpty) {
      stdout.writeln(
        '  3. Wire each plugin (import package:<plugin>/<plugin>.dart) — they do nothing until you do:',
      );
      for (final MapEntry(key: plugin, value: line) in unwired.entries) {
        stdout.writeln('       $plugin:  $line');
      }
    } else if (detected.isNotEmpty) {
      stdout.writeln(
        '  3. Plugins: already wired (${detected.keys.join(', ')}).',
      );
    }
    stdout.writeln(
      '  ${detected.isEmpty ? 3 : 4}. flutterpilot mcp install (connects Claude Code, '
      'Cursor, VS Code, Codex, Gemini CLI and more), then flutterpilot dev (runs the app so the server finds it).',
    );
  }

  /// Whether flutterpilot_sdk is published on pub.dev (so `init` can use
  /// hosted versions). Offline or slow: false, and git is used.
  static Future<bool> onPubDev() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(
        Uri.parse('https://pub.dev/api/packages/flutterpilot_sdk'),
      );
      final res = await req.close().timeout(const Duration(seconds: 3));
      await res.drain<void>();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// macOS apps run sandboxed: without `com.apple.security.network.client`
  /// every HTTP request fails with errno = 1. Adds it to both entitlement
  /// files when the project has a macOS runner; returns lines for the user.
  static List<String> addMacosNetworkClient(String rootPath) {
    final runner = Directory(p.join(rootPath, 'macos', 'Runner'));
    if (!runner.existsSync()) return const [];
    final out = <String>[];
    for (final name in ['DebugProfile', 'Release']) {
      final file = File(p.join(runner.path, '$name.entitlements'));
      final rel = 'macos/Runner/$name.entitlements';
      if (!file.existsSync()) {
        out.add(
          '⚠️ No $rel: add com.apple.security.network.client to your '
          'macOS entitlements so HTTP works.',
        );
        continue;
      }
      final content = file.readAsStringSync();
      final patched = withNetworkClient(content);
      if (patched == null) {
        out.add(
          '⚠️ Could not edit $rel: add <key>com.apple.security.'
          'network.client</key><true/> yourself so HTTP works.',
        );
      } else if (patched != content) {
        file.writeAsStringSync(patched);
        out.add(
          '✅ Added the network.client entitlement to $rel '
          '(macOS HTTP needs it).',
        );
      }
    }
    return out;
  }

  /// [plist] with `com.apple.security.network.client` set to true before
  /// the top-level `</dict>`; unchanged if the key is there (even false:
  /// that's the developer's choice); null if there's no `</dict>`.
  static String? withNetworkClient(String plist) {
    const key = 'com.apple.security.network.client';
    if (plist.contains('<key>$key</key>')) return plist;
    final end = plist.lastIndexOf('</dict>');
    if (end < 0) return null;
    // Match the file's indentation (Flutter's template uses a tab).
    final indent =
        RegExp(r'\n([ \t]+)<key>').firstMatch(plist)?.group(1) ?? '\t';
    return '${plist.substring(0, end)}$indent<key>$key</key>\n'
        '$indent<true/>\n${plist.substring(end)}';
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
