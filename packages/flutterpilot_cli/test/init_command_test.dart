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

    test('fails with UsageException when pubspec.yaml is missing', () {
      final empty = Directory.systemTemp.createTempSync('fp_empty_');
      addTearDown(() => empty.deleteSync(recursive: true));
      expect(
        runner.run(['init', '-p', empty.path]),
        throwsA(isA<UsageException>()),
      );
    });

    test(
      'adds git deps for sdk + detected plugins and overrides the sdk',
      () async {
        await runner.run(['init', '-p', tempDir.path]);
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
        await runner.run(['init', '-p', tempDir.path]);

        final mainContent = mainFile.readAsStringSync();
        expect(mainContent.contains('FlutterPilot.initialize();'), isTrue);
        expect(mainContent.contains('NavigationTracker()'), isTrue);
        expect(mainContent.contains('FlutterPilot.localeNotifier'), isTrue);
        expect(mainContent.contains('FlutterPilot.textScaleNotifier'), isTrue);
        expect(mainContent.contains('ValueListenableBuilder<Locale?>'), isTrue);
        expect(mainContent.contains('ValueListenableBuilder<double?>'), isTrue);
        // A non-const observer inside `const MaterialApp(` would not compile.
        expect(mainContent, isNot(contains('const MaterialApp')));
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

    test('addValueListenableOverrides wraps MaterialApp idempotently', () {
      const input = 'MaterialApp(home: Scaffold())';
      final wrapped = InitCommand.addValueListenableOverrides(input);
      expect(wrapped, contains('ValueListenableBuilder<Locale?>'));
      expect(wrapped, contains('ValueListenableBuilder<double?>'));
      expect(wrapped, contains('FlutterPilot.localeNotifier'));
      expect(wrapped, contains('FlutterPilot.textScaleNotifier'));
      expect(InitCommand.addValueListenableOverrides(wrapped), wrapped);
    });
  });
}
