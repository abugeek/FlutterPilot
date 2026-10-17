import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:fp_cli/fp_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _Capture implements Stdout {
  _Capture(this.buffer);
  final StringBuffer buffer;

  @override
  void write(Object? object) => buffer.write(object);
  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MigrateCommand', () {
    late Directory tempDir;
    late CommandRunner<void> runner;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('fp_migrate_test_');
      runner = CommandRunner<void>('fp', '')..addCommand(MigrateCommand());

      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: legacy_app
dependencies:
  flutter:
    sdk: flutter
  flutterpilot_sdk: ^0.1.0
  flutterpilot_supabase: ^0.1.0

dev_dependencies:
  flutterpilot_cli: ^0.1.0
''');

      final toolDir = Directory(p.join(tempDir.path, 'tool'))..createSync();
      File(p.join(toolDir.path, 'pilot_main.dart')).writeAsStringSync('''
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';
import 'package:flutterpilot_supabase/flutterpilot_supabase.dart';
import '../lib/main.dart' as app;

void main() {
  FlutterPilot.init();
  app.main();
}
''');

      File(p.join(tempDir.path, '.mcp.json')).writeAsStringSync('''
{
  "mcpServers": {
    "FlutterPilot": {
      "command": "dart",
      "args": ["run", "flutterpilot_server"]
    }
  }
}
''');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('dry-run reports changes without mutating files', () async {
      final out = StringBuffer();
      final sink = _Capture(out);
      await IOOverrides.runZoned(
        () => runner.run(['migrate', '-p', tempDir.path, '--dry-run']),
        stdout: () => sink,
      );

      final output = out.toString();
      expect(output, contains('Would update pubspec.yaml'));
      expect(output, contains('Would update tool/pilot_main.dart'));
      expect(output, contains('Would update .mcp.json'));

      // Files remain unchanged
      final pubspec = File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('flutterpilot_sdk:'));
      expect(pubspec, isNot(contains('fp_sdk:')));
    });

    test('performs full migration of pubspec, dart imports, and mcp configs', () async {
      final out = StringBuffer();
      final sink = _Capture(out);
      await IOOverrides.runZoned(
        () => runner.run(['migrate', '-p', tempDir.path]),
        stdout: () => sink,
      );

      final output = out.toString();
      expect(output, contains('Updated pubspec.yaml'));
      expect(output, contains('Updated tool/pilot_main.dart'));
      expect(output, contains('Updated .mcp.json'));
      expect(output, contains('Completed migration across 3 file(s)'));

      // Verify pubspec
      final pubspec = File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('fp_sdk: ^0.1.0'));
      expect(pubspec, contains('fp_supabase: ^0.1.0'));
      expect(pubspec, contains('fp_cli: ^0.1.0'));
      expect(pubspec, isNot(contains('flutterpilot_sdk')));

      // Verify Dart imports
      final dartContent = File(p.join(tempDir.path, 'tool', 'pilot_main.dart')).readAsStringSync();
      expect(dartContent, contains("import 'package:fp_sdk/flutterpilot_sdk.dart';"));
      expect(dartContent, contains("import 'package:fp_supabase/flutterpilot_supabase.dart';"));
      expect(dartContent, isNot(contains('package:flutterpilot_sdk/')));

      // Verify .mcp.json
      final mcpContent = File(p.join(tempDir.path, '.mcp.json')).readAsStringSync();
      expect(mcpContent, contains('"fp_server"'));
      expect(mcpContent, isNot(contains('"flutterpilot_server"')));

      // Second run reports already migrated
      final out2 = StringBuffer();
      final sink2 = _Capture(out2);
      await IOOverrides.runZoned(
        () => runner.run(['migrate', '-p', tempDir.path]),
        stdout: () => sink2,
      );
      expect(out2.toString(), contains('Project is already fully migrated to fp_*!'));
    });
  });
}
