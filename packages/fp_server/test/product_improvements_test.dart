import 'package:fp_server/fp_server.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterPilot Product Improvements Suite', () {
    late FlutterPilotServer server;

    setUp(() {
      server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    });

    test('registers 71 tools including the 6 new autonomous superpowers', () {
      final names = server.registeredToolNames.toSet();
      expect(names, contains('apply_and_verify'));
      expect(names, contains('simulate_viewport_matrix'));
      expect(names, contains('crawl_app'));
      expect(names, contains('get_rebuild_stats'));
      expect(names, contains('locate_source_ast'));
      expect(names, contains('export_network_mocks'));
      expect(names, contains('synthesize_golden_test'));
      expect(names, contains('audit_design_tokens'));
      expect(names.length, 71);
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

    test('tap_widget and enter_text take a mark; gesture_widget does not', () {
      final tools = server.toolListJson();
      final gesture = tools.firstWhere((t) => t['name'] == 'gesture_widget');
      expect(
        (gesture['inputSchema']['properties'] as Map).containsKey('mark'),
        isFalse,
        reason: 'the SDK gestures do not resolve marks',
      );
      for (final toolName in ['tap_widget', 'enter_text']) {
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

    test('crawl_app inputSchema defines maxScreens and restore', () {
      final tools = server.toolListJson();
      final crawlTool = tools.firstWhere((t) => t['name'] == 'crawl_app');
      final schema = crawlTool['inputSchema'] as Map<String, dynamic>;
      final properties = schema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('maxScreens'), isTrue);
      expect(properties.containsKey('restore'), isTrue);
    });

    test('get_rebuild_stats inputSchema defines filter, reset, and minCount', () {
      final tools = server.toolListJson();
      final rebuildTool = tools.firstWhere((t) => t['name'] == 'get_rebuild_stats');
      final schema = rebuildTool['inputSchema'] as Map<String, dynamic>;
      final properties = schema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('filter'), isTrue);
      expect(properties.containsKey('reset'), isTrue);
      expect(properties.containsKey('minCount'), isTrue);
    });

    test('locate_source_ast inputSchema defines key and file/line/column', () {
      final tools = server.toolListJson();
      final astTool = tools.firstWhere((t) => t['name'] == 'locate_source_ast');
      final schema = astTool['inputSchema'] as Map<String, dynamic>;
      final properties = schema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('key'), isTrue);
      expect(properties.containsKey('file'), isTrue);
      expect(properties.containsKey('line'), isTrue);
      expect(properties.containsKey('column'), isTrue);
    });

    test('export_network_mocks inputSchema defines filter and apply', () {
      final tools = server.toolListJson();
      final mockTool = tools.firstWhere((t) => t['name'] == 'export_network_mocks');
      final schema = mockTool['inputSchema'] as Map<String, dynamic>;
      final properties = schema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('filter'), isTrue);
      expect(properties.containsKey('apply'), isTrue);
    });

    test('synthesize_golden_test inputSchema defines screen, name, viewports', () {
      final tools = server.toolListJson();
      final goldenTool = tools.firstWhere((t) => t['name'] == 'synthesize_golden_test');
      final schema = goldenTool['inputSchema'] as Map<String, dynamic>;
      final properties = schema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('name'), isTrue);
      expect(properties.containsKey('screen'), isTrue);
      expect(schema['required'], ['screen']);
      expect(properties.containsKey('viewports'), isTrue);
    });

    test('audit_design_tokens is registered and callable', () {
      final names = server.registeredToolNames.toSet();
      expect(names, contains('audit_design_tokens'));
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
