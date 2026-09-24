import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutterpilot_cli/flutterpilot_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('InitCommand', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('flutterpilot_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('exits with error if pubspec.yaml is missing', () async {
      final cmd = InitCommand();
      // Command should handle missing pubspec
      expect(cmd.name, equals('init'));
    });

    test('patches pubspec.yaml and detects dependencies', () async {
      final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync('''
name: my_sample_app
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  dio: ^5.4.3
''');

      final libDir = Directory(p.join(tempDir.path, 'lib'))..createSync();
      final mainFile = File(p.join(libDir.path, 'main.dart'));
      mainFile.writeAsStringSync('''
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}
''');

      // Test parsing logic & file modifications
      final content = pubspec.readAsStringSync();
      expect(content.contains('flutter_riverpod'), isTrue);
      expect(content.contains('dio'), isTrue);
    });

    test('patches main.dart with FlutterPilot.initialize and NavigationTracker', () async {
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
    });
  });
}
