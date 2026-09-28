import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutterpilot_cli/flutterpilot_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('InitCommand', () {
    late Directory tempDir;
    late CommandRunner<void> runner;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('flutterpilot_test_');
      runner = CommandRunner<void>('flutterpilot', '')
        ..addCommand(InitCommand());
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: my_sample_app
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  dio: ^5.4.3
''');
      Directory(p.join(tempDir.path, 'lib')).createSync();
      File(p.join(tempDir.path, 'lib', 'main.dart')).writeAsStringSync('''
import 'package:flutter/material.dart';

Future<void> main() async {
  runApp(const MyApp());
}
''');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('a second run changes nothing and asks for no wiring done', () async {
      Future<String> initOutput() async {
        final out = StringBuffer();
        final sink = _Capture(out);
        await IOOverrides.runZoned(
          () => runner.run(['init', '-p', tempDir.path, '--source', 'git']),
          stdout: () => sink,
        );
        return out.toString();
      }

      final first = await initOutput();
      expect(first, contains('✅ Updated pubspec.yaml.'));
      expect(first, contains('flutterpilot_dio:  DioPilotInterceptor'));
      final main = File(p.join(tempDir.path, 'lib', 'main.dart'));
      main.writeAsStringSync(
        '${main.readAsStringSync()}\n// DioPilotInterceptor.register();\n',
      );
      final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
      final before = pubspec.readAsStringSync();
      final second = await initOutput();
      expect(pubspec.readAsStringSync(), before);
      expect(second, contains('pubspec.yaml already has FlutterPilot'));
      expect(second, isNot(contains('flutterpilot_dio:  ')));
      // Riverpod is still not wired: it is still listed.
      expect(second, contains('flutterpilot_riverpod:  '));
    });

    test('adds the Firebase plugin for Auth/Firestore, not firebase_core '
        'alone', () async {
      Future<YamlMap> depsFor(String firebaseDeps) async {
        File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: my_sample_app
dependencies:
  flutter:
    sdk: flutter
$firebaseDeps''');
        await runner.run(['init', '-p', tempDir.path, '--source', 'git']);
        final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
        return (loadYaml(pubspec.readAsStringSync()) as YamlMap)['dependencies']
            as YamlMap;
      }

      expect(
        (await depsFor(
          '  firebase_core: ^4.0.0\n  firebase_analytics: ^12.0.0\n',
        )).containsKey('flutterpilot_firebase'),
        isFalse,
      );
      expect(
        (await depsFor(
          '  firebase_core: ^4.0.0\n  cloud_firestore: ^6.0.0\n',
        )).containsKey('flutterpilot_firebase'),
        isTrue,
      );
    });

    test('fails with UsageException when pubspec.yaml is missing', () {
      final empty = Directory.systemTemp.createTempSync('fp_empty_');
      addTearDown(() => empty.deleteSync(recursive: true));
      expect(
        runner.run(['init', '-p', empty.path]),
        throwsA(isA<UsageException>()),
      );
    });

    test('hosted: this release from pub.dev, and no sdk override', () async {
      // An earlier git init left an override; hosted packages don't need it.
      await runner.run(['init', '-p', tempDir.path, '--source', 'git']);
      await runner.run(['init', '-p', tempDir.path, '--source', 'hosted']);
      final yaml =
          loadYaml(
                File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync(),
              )
              as YamlMap;
      final deps = yaml['dependencies'] as YamlMap;
      expect(deps['flutterpilot_sdk'], '^$flutterpilotVersion');
      expect(deps['flutterpilot_dio'], '^$flutterpilotVersion');
      expect(yaml['dependency_overrides'], isNull);
    });

    test('flutterpilotVersion matches pubspec.yaml', () {
      final pubspec =
          loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
      expect(flutterpilotVersion, pubspec['version']);
    });

    test(
      'adds git deps for sdk + detected plugins and overrides the sdk',
      () async {
        await runner.run(['init', '-p', tempDir.path, '--source', 'git']);
        final yaml =
            loadYaml(
                  File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync(),
                )
                as YamlMap;
        final deps = yaml['dependencies'] as YamlMap;

        expect(
          deps['flutterpilot_sdk']['git']['path'],
          'packages/flutterpilot_sdk',
        );
        expect(
          deps['flutterpilot_dio']['git']['path'],
          'packages/plugins/flutterpilot_dio',
        );
        expect(deps['flutterpilot_riverpod'], isNotNull);
        expect(deps.containsKey('flutterpilot_bloc'), isFalse);
        expect(yaml['dev_dependencies'], isNull);
        expect(
          yaml['dependency_overrides']['flutterpilot_sdk']['git'],
          isNotNull,
        );

        final main = File(
          p.join(tempDir.path, 'lib', 'main.dart'),
        ).readAsStringSync();
        expect(
          main,
          contains("import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';"),
        );
        expect(
          main,
          contains(
            'async {\n  WidgetsFlutterBinding.ensureInitialized();\n  FlutterPilot.initialize();',
          ),
        );
      },
    );

    test('--local uses relative path deps', () async {
      final repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));
      await runner.run(['init', '-p', tempDir.path, '--local', repoRoot]);
      final yaml =
          loadYaml(
                File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync(),
              )
              as YamlMap;
      final sdkPath =
          yaml['dependencies']['flutterpilot_sdk']['path'] as String;
      expect(
        p.normalize(p.join(tempDir.path, sdkPath)),
        p.join(repoRoot, 'packages', 'flutterpilot_sdk'),
      );
    });

    test('patchMain is idempotent', () {
      final once = InitCommand.patchMain(
        'void main() {\n  runApp(App());\n}\n',
      )!;
      expect(InitCommand.patchMain(once), once);
      expect(InitCommand.patchMain('// no entrypoint'), isNull);
    });

    test(
      'patches main.dart with FlutterPilot.initialize and NavigationTracker',
      () async {
        final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
        pubspec.writeAsStringSync('''
name: my_sample_app
dependencies:
  flutter:
    sdk: flutter
''');

        final libDir = Directory(p.join(tempDir.path, 'lib'))..createSync();
        final mainFile = File(p.join(libDir.path, 'main.dart'));
        mainFile.writeAsStringSync('''
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(home: Scaffold()));
}
''');

        final runner = CommandRunner<void>('flutterpilot', 'CLI')
          ..addCommand(InitCommand());
        await runner.run(['init', '-p', tempDir.path, '--source', 'git']);

        final mainContent = mainFile.readAsStringSync();
        expect(mainContent.contains('FlutterPilot.initialize();'), isTrue);
        expect(mainContent.contains('NavigationTracker()'), isTrue);
        // A non-const observer inside `const MaterialApp(` would not compile.
        expect(mainContent, isNot(contains('const MaterialApp')));
        // set_app_settings(locale/textScale) needs no wiring in the app.
        expect(mainContent, isNot(contains('ValueListenableBuilder')));
      },
    );

    test('addNavigationTracker extends existing observers, skips .router', () {
      expect(
        InitCommand.addNavigationTracker(
          'MaterialApp(navigatorObservers: [MyObs()], home: X())',
        ),
        'MaterialApp(navigatorObservers: [NavigationTracker(), MyObs()], home: X())',
      );
      const router = 'MaterialApp.router(routerConfig: r)';
      expect(InitCommand.addNavigationTracker(router), router);
    });

    group('route tracking step', () {
      String step(
        String main, {
        bool added = false,
        bool before = false,
        bool goRouter = false,
      }) => InitCommand.routeTrackingStep(
        main,
        trackerAdded: added,
        trackedBefore: before,
        goRouter: goRouter,
      );

      test('says what init added, not "already wired"', () {
        expect(step('MaterialApp(', added: true), contains('added'));
        expect(step('MaterialApp(', added: true), isNot(contains('already')));
      });

      test('an existing tracker is already wired', () {
        expect(
          step(
            'MaterialApp(navigatorObservers: [NavigationTracker()])',
            before: true,
          ),
          contains('already wired'),
        );
      });

      test('go_router points to its plugin, never "already wired"', () {
        final out = step(
          'MaterialApp.router(routerConfig: router)',
          goRouter: true,
        );
        expect(out, contains('flutterpilot_gorouter'));
        expect(out, isNot(contains('already wired')));
      });

      test('another .router app is told how routes are named', () {
        final out = step('MaterialApp.router(routerConfig: r)');
        expect(out, contains("can't take NavigationTracker"));
        expect(out, isNot(contains('already wired')));
      });

      test('no MaterialApp in main.dart asks to add the observer', () {
        expect(
          step('void main() => runApp(const App());'),
          contains('Add `navigatorObservers: [NavigationTracker()]`'),
        );
      });
    });

    test('patchMain handles arrow-bodied main', () {
      final out = InitCommand.patchMain('void main() => runApp(const App());')!;
      expect(out, contains('FlutterPilot.initialize();'));
      expect(out, contains('runApp(const App());'));
      expect(out, isNot(contains('=>')));
    });

    test('ensureImport adds the SDK import when injected code needs it', () {
      expect(
        InitCommand.ensureImport('x(NavigationTracker())'),
        startsWith("import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';"),
      );
      expect(InitCommand.ensureImport('plain()'), 'plain()');
    });

    test('patchMain reuses an existing ensureInitialized()', () {
      final out = InitCommand.patchMain('''
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setup();
  runApp(const App());
}
''')!;
      expect(
        'WidgetsFlutterBinding.ensureInitialized()'.allMatches(out).length,
        1,
      );
      expect(
        out,
        contains(
          'WidgetsFlutterBinding.ensureInitialized();\n  FlutterPilot.initialize();',
        ),
      );
    });
  });

  group('macOS network.client entitlement', () {
    const template = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
</dict>
</plist>
''';
    late Directory app;
    setUp(() => app = Directory.systemTemp.createTempSync('fp_ent_'));
    tearDown(() => app.deleteSync(recursive: true));

    test('is added before </dict> in the file\'s indentation', () {
      final out = InitCommand.withNetworkClient(template)!;
      expect(
        out,
        contains(
          '\t<key>com.apple.security.network.server</key>\n\t<true/>\n'
          '\t<key>com.apple.security.network.client</key>\n\t<true/>\n'
          '</dict>',
        ),
      );
    });

    test('an existing key is left alone, even false', () {
      final off = template.replaceFirst(
        '</dict>',
        '\t<key>com.apple.security.network.client</key>\n\t<false/>\n</dict>',
      );
      expect(InitCommand.withNetworkClient(off), off);
      final once = InitCommand.withNetworkClient(template)!;
      expect(InitCommand.withNetworkClient(once), once);
      expect(InitCommand.withNetworkClient('<plist/>'), isNull);
    });

    test('init adds it to both files when the app supports macOS', () async {
      File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync(
        'name: a\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      for (final f in ['DebugProfile', 'Release']) {
        File(p.join(app.path, 'macos', 'Runner', '$f.entitlements'))
          ..createSync(recursive: true)
          ..writeAsStringSync(template);
      }
      await (CommandRunner<void>('flutterpilot', '')..addCommand(InitCommand()))
          .run(['init', '-p', app.path, '--source', 'git']);
      for (final f in ['DebugProfile', 'Release']) {
        expect(
          File(
            p.join(app.path, 'macos', 'Runner', '$f.entitlements'),
          ).readAsStringSync(),
          contains('<key>com.apple.security.network.client</key>'),
        );
      }
    });

    test('no macOS runner: nothing to do', () {
      expect(InitCommand.addMacosNetworkClient(app.path), isEmpty);
      expect(Directory(p.join(app.path, 'macos')).existsSync(), isFalse);
    });
  });
}

/// Collects what `init` prints.
class _Capture implements Stdout {
  _Capture(this._out);
  final StringBuffer _out;
  @override
  void writeln([Object? o = '']) => _out.writeln(o);
  @override
  void write(Object? o) => _out.write(o);
  @override
  dynamic noSuchMethod(Invocation i) => null;
}
