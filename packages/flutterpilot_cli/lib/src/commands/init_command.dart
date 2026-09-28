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
    'dio.interceptors.add(DioPilotInterceptor());  // on every Dio you create',
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

    var overridesAdded = false;
    if (mainFile.existsSync()) {
      final content = await mainFile.readAsString();
      final withOverrides = addValueListenableOverrides(content);
      if (withOverrides != content) {
        await mainFile.writeAsString(withOverrides);
        overridesAdded = true;
        final wired = wiredOverrides(withOverrides);
        stdout.writeln(
          '✅ Wired MaterialApp for $wired overrides '
          '(set_locale / set_text_scale_factor).',
        );
        if (!wired.contains('locale')) {
          stdout.writeln(
            '   Skipped locale: MaterialApp already sets locale:, so set_locale '
            'would change nothing.',
          );
        }
        if (!wired.contains('text scale')) {
          stdout.writeln(
            '   Skipped text scale: MaterialApp has its own builder:. Apply '
            'FlutterPilot.textScaleNotifier inside it to use set_text_scale_factor.',
          );
        }
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
      trackerAdded
          ? '  2. (route tracking already wired)'
          : '  2. Add `navigatorObservers: [NavigationTracker()]` to your MaterialApp (skip if using go_router).',
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
      '  ${detected.isEmpty ? 3 : 4}. flutter run, then connect your agent to the FlutterPilot MCP server.',
    );
    if (!overridesAdded && mainFile.existsSync()) {
      final content = await mainFile.readAsString();
      if (!content.contains('FlutterPilot.localeNotifier')) {
        stdout.writeln(
          '\nTip: To enable runtime locale and text scale overrides (set_locale / set_text_scale), '
          'wrap MaterialApp in ValueListenableBuilder with FlutterPilot.localeNotifier and FlutterPilot.textScaleNotifier.',
        );
      }
    }
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

  /// Wraps `MaterialApp` in `ValueListenableBuilder`s for locale and text scale overrides.
  static String addValueListenableOverrides(String content) {
    if (content.contains('FlutterPilot.localeNotifier') ||
        content.contains('FlutterPilot.textScaleNotifier')) {
      return content;
    }
    final app = RegExp(r'(?:const\s+)?(MaterialApp(?:\.router)?\s*\()');
    final match = app.firstMatch(content);
    if (match == null) return content;

    final openParenIndex = match.end - 1;
    final closeParenIndex = _findMatchingClosingParen(content, openParenIndex);
    if (closeParenIndex == -1) return content;

    var appCode = content.substring(match.start, closeParenIndex + 1);
    appCode = appCode.replaceFirst(RegExp(r'^const\s+'), '');

    // Only wire what will take effect. If the app already sets `locale:` or
    // has its own `builder:`, leave that override unwired: a listener that
    // changes nothing would make set_locale/set_text_scale_factor report a
    // false success.
    final wireLocale = !_hasTopLevelArg(appCode, 'locale');
    final wireScale = !_hasTopLevelArg(appCode, 'builder');
    if (!wireLocale && !wireScale) return content;

    if (wireLocale) {
      final insertIdx = appCode.indexOf('(') + 1;
      appCode =
          '${appCode.substring(0, insertIdx)}\n      locale: pilotLocale,${appCode.substring(insertIdx)}';
    }
    if (wireScale) {
      final insertIdx = appCode.indexOf('(') + 1;
      appCode = '''${appCode.substring(0, insertIdx)}
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: pilotScale != null
                ? TextScaler.linear(pilotScale)
                : media.textScaler,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },${appCode.substring(insertIdx)}''';
    }

    var wrapped = appCode;
    if (wireScale) {
      wrapped =
          '''ValueListenableBuilder<double?>(
    valueListenable: FlutterPilot.textScaleNotifier,
    builder: (context, pilotScale, _) => $wrapped,
  )''';
    }
    if (wireLocale) {
      wrapped =
          '''ValueListenableBuilder<Locale?>(
  valueListenable: FlutterPilot.localeNotifier,
  builder: (context, pilotLocale, _) => $wrapped,
)''';
    }

    return content.replaceRange(match.start, closeParenIndex + 1, wrapped);
  }

  /// Whether the call [code] (e.g. `MaterialApp(...)`) passes [name] as one
  /// of its own arguments — not a nested widget's (`home: X(builder: ...)`).
  static bool _hasTopLevelArg(String code, String name) {
    final arg = RegExp('^\\s*$name\\s*:');
    var depth = 0;
    for (var i = 0; i < code.length; i++) {
      final ch = code[i];
      if ('([{'.contains(ch)) {
        depth++;
        if (depth == 1 && arg.hasMatch(code.substring(i + 1))) return true;
      } else if (')]}'.contains(ch)) {
        depth--;
      } else if (ch == ',' &&
          depth == 1 &&
          arg.hasMatch(code.substring(i + 1))) {
        return true;
      }
    }
    return false;
  }

  /// What [addValueListenableOverrides] wired into [content], for the
  /// summary line: 'locale and text scale', 'locale', 'text scale' or ''.
  static String wiredOverrides(String content) => [
    if (content.contains('FlutterPilot.localeNotifier')) 'locale',
    if (content.contains('FlutterPilot.textScaleNotifier')) 'text scale',
  ].join(' and ');

  static int _findMatchingClosingParen(String text, int openParenIndex) {
    var depth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inLineComment = false;
    var inBlockComment = false;

    for (var i = openParenIndex; i < text.length; i++) {
      final ch = text[i];
      final next = i + 1 < text.length ? text[i + 1] : '';

      if (inLineComment) {
        if (ch == '\n') inLineComment = false;
        continue;
      }
      if (inBlockComment) {
        if (ch == '*' && next == '/') {
          inBlockComment = false;
          i++;
        }
        continue;
      }
      if (inSingleQuote) {
        if (ch == '\\') {
          i++;
        } else if (ch == "'") {
          inSingleQuote = false;
        }
        continue;
      }
      if (inDoubleQuote) {
        if (ch == '\\') {
          i++;
        } else if (ch == '"') {
          inDoubleQuote = false;
        }
        continue;
      }

      if (ch == '/' && next == '/') {
        inLineComment = true;
        i++;
        continue;
      }
      if (ch == '/' && next == '*') {
        inBlockComment = true;
        i++;
        continue;
      }
      if (ch == "'") {
        inSingleQuote = true;
        continue;
      }
      if (ch == '"') {
        inDoubleQuote = true;
        continue;
      }

      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
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
