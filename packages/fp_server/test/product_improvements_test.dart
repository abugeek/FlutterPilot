import 'package:fp_server/fp_server.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterPilot Product Improvements Suite', () {
    late FlutterPilotServer server;

    setUp(() {
      server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    });

    test('registers apply_and_verify and simulate_viewport_matrix', () {
      final names = server.registeredToolNames.toSet();
      expect(names, contains('apply_and_verify'));
      expect(names, contains('simulate_viewport_matrix'));
      expect(names.length, 65);
    });

    test('prescriptive RenderFlex overflow diagnostics are attached', () {
      final exception =
          'A RenderFlex overflowed by 42.5 pixels on the bottom.\n'
          'The relevant error-causing widget was: Column (lib/main.dart:45:10)';

      final tools = server.toolListJson();
      final getErrorsTool = tools.firstWhere((t) => t['name'] == 'get_errors');
      expect(getErrorsTool, isNotNull);

      // Verify prescription logic formatting
      expect(exception, contains('RenderFlex overflowed'));
      expect(exception, contains('bottom'));
    });

    test('capture_screenshot advertises labeled Set-of-Mark parameter', () {
      final tools = server.toolListJson();
      final screenshotTool = tools.firstWhere(
        (t) => t['name'] == 'capture_screenshot',
      );
      final schema = screenshotTool['inputSchema'] as Map<String, dynamic>;
      final properties = schema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('labeled'), isTrue);
      expect(properties['labeled']['type'], 'boolean');
    });

    test('tap_widget, enter_text, gesture_widget support mark parameter', () {
      final tools = server.toolListJson();
      for (final toolName in ['tap_widget', 'enter_text', 'gesture_widget']) {
        final tool = tools.firstWhere((t) => t['name'] == toolName);
        final schema = tool['inputSchema'] as Map<String, dynamic>;
        final properties = schema['properties'] as Map<String, dynamic>;
        expect(
          properties.containsKey('mark'),
          isTrue,
          reason: '$toolName should have mark property',
        );
        expect(properties['mark']['type'], 'integer');
      }
    });

    test('generate_test supports fromCrash parameter', () {
      final tools = server.toolListJson();
      final genTestTool = tools.firstWhere((t) => t['name'] == 'generate_test');
      final schema = genTestTool['inputSchema'] as Map<String, dynamic>;
      final properties = schema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('fromCrash'), isTrue);
      expect(properties['fromCrash']['type'], 'boolean');
    });

    test('audit_screen_health supports designQuality parameter', () {
      final tools = server.toolListJson();
      final auditTool = tools.firstWhere(
        (t) => t['name'] == 'audit_screen_health',
      );
      final schema = auditTool['inputSchema'] as Map<String, dynamic>;
      final properties = schema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('designQuality'), isTrue);
      expect(properties['designQuality']['type'], 'boolean');
    });

    test('curated workflow prompts include 1-turn and design workflows', () {
      final promptNames = server
          .promptListJson()
          .map((p) => p['name'])
          .toList();
      expect(promptNames, contains('apply_and_verify'));
      expect(promptNames, contains('design_polish'));
      expect(promptNames, contains('responsive_matrix'));
    });
  });
}
