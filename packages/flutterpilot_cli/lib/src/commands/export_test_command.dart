import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:vm_service/vm_service_io.dart';

/// Command to export interactive flight sessions into Patrol, Integration Test, or Widget Test suites.
class ExportTestCommand extends Command<void> {
  @override
  final String name = 'export-test';

  @override
  final String description =
      'Export recorded interactive user journeys to a Patrol, Integration, or Widget test suite.';

  ExportTestCommand() {
    argParser
      ..addOption(
        'framework',
        abbr: 'f',
        defaultsTo: 'patrol',
        allowed: ['patrol', 'integration', 'widget'],
        help: 'Target test framework to synthesize.',
      )
      ..addOption(
        'name',
        abbr: 'n',
        defaultsTo: 'User Journey Flow',
        help: 'Name of the test case.',
      )
      ..addOption(
        'widget',
        abbr: 'w',
        defaultsTo: 'MyApp()',
        help: 'Target widget/screen name to mount.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Path to write the synthesized test file (e.g. integration_test/flow_test.dart).',
      )
      ..addOption(
        'vm-uri',
        abbr: 'u',
        help: 'VM Service URI of the running Flutter application (e.g. ws://127.0.0.1:8181/ws).',
      );
  }

  @override
  Future<void> run() async {
    final framework = argResults?['framework'] as String? ?? 'patrol';
    final testName = argResults?['name'] as String? ?? 'User Journey Flow';
    final appWidget = argResults?['widget'] as String? ?? 'MyApp()';
    final customOutput = argResults?['output'] as String?;
    var vmUri = argResults?['vm-uri'] as String?;

    if (vmUri == null || vmUri.isEmpty) {
      // Default to standard local VM service if not specified
      vmUri = 'ws://127.0.0.1:8181/ws';
    }

    stdout.writeln('Connecting to Flutter VM service at $vmUri...');
    try {
      final service = await vmServiceConnectUri(vmUri);
      final vm = await service.getVM();
      final isolateId = vm.isolates?.firstOrNull?.id;

      if (isolateId == null) {
        stderr.writeln('❌ No active isolate found.');
        return;
      }

      stdout.writeln('Synthesizing $framework test suite from flight recorder...');
      final response = await service.callServiceExtension(
        'ext.flutterpilot.exportTestSuite',
        isolateId: isolateId,
        args: {
          'framework': framework,
          'testName': testName,
          'appWidget': appWidget,
        },
      );

      final code = response.json?['code']?.toString() ?? '';
      if (code.isEmpty) {
        stderr.writeln('❌ Failed to retrieve generated test code.');
        return;
      }

      final defaultPath = framework == 'widget'
          ? 'test/flow_test.dart'
          : 'integration_test/flow_test.dart';
      final outputPath = customOutput ?? defaultPath;

      final file = File(outputPath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.writeAsStringSync(code);

      stdout.writeln('✅ Test suite successfully exported to $outputPath!');
      stdout.writeln('\nTo run this test:');
      if (framework == 'patrol') {
        stdout.writeln('  patrol test $outputPath');
      } else {
        stdout.writeln('  flutter test $outputPath');
      }
    } catch (e) {
      stderr.writeln('⚠️ Connection error: $e');
      stderr.writeln('Make sure your Flutter application is running with FlutterPilot initialized.');
    }
  }
}
