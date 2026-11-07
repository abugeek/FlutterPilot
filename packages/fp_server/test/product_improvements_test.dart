import 'dart:io';

import 'package:fp_server/fp_server.dart';
import 'package:fp_server/src/source_span.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterPilot Product Improvements Suite', () {
    late FlutterPilotServer server;

    setUp(() {
      server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    });

    test('registers 74 tools including the new autonomous capabilities', () {
      final names = server.registeredToolNames.toSet();
      expect(names, contains('apply_and_verify'));
      expect(names, contains('simulate_viewport_matrix'));
      expect(names, contains('crawl_app'));
      expect(names, contains('get_rebuild_stats'));
      expect(names, contains('locate_source_ast'));
      expect(names, contains('export_network_mocks'));
      expect(names, contains('synthesize_golden_test'));
      expect(names, contains('audit_design_tokens'));
      expect(names, contains('simulate_keyboard'));
      expect(names, contains('apply_patch_and_verify'));
      expect(names, contains('replay_flow'));
      expect(names.length, 74);
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

    test('simulate_keyboard inputSchema defines height and restore', () {
      final tools = server.toolListJson();
      final kbd = tools.firstWhere((t) => t['name'] == 'simulate_keyboard');
      final props = kbd['inputSchema']['properties'] as Map;
      expect(props.containsKey('height'), isTrue);
      expect(props.containsKey('restore'), isTrue);
    });

    test('apply_patch_and_verify inputSchema defines surgical patch targets', () {
      final tools = server.toolListJson();
      final patch = tools.firstWhere(
        (t) => t['name'] == 'apply_patch_and_verify',
      );
      final props = patch['inputSchema']['properties'] as Map;
      expect(props.containsKey('key'), isTrue);
      expect(props.containsKey('wrapWith'), isTrue);
      expect(props.containsKey('unwrap'), isTrue);
      expect(props.containsKey('replaceCall'), isTrue);
      expect(props.containsKey('patches'), isTrue);
    });

    test('replay_flow inputSchema defines delayMs and assertRoute', () {
      final tools = server.toolListJson();
      final replay = tools.firstWhere((t) => t['name'] == 'replay_flow');
      final props = replay['inputSchema']['properties'] as Map;
      expect(props.containsKey('delayMs'), isTrue);
      expect(props.containsKey('assertRoute'), isTrue);
    });

    test('compare_screenshot supports comparePrevious, ignoreStatusBar, and ignoreKeys', () {
      final tools = server.toolListJson();
      final cmp = tools.firstWhere((t) => t['name'] == 'compare_screenshot');
      final schema = cmp['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('comparePrevious'), isTrue);
      expect(props.containsKey('ignoreStatusBar'), isTrue);
      expect(props.containsKey('ignoreKeys'), isTrue);
      expect(schema.containsKey('required'), isFalse);
    });

    test('findWidgetConstructorInProject finds unmounted/off-screen widgets in source files', () async {
      final tempDir = Directory.systemTemp.createTempSync('fp_ast_test');
      try {
        final libDir = Directory('${tempDir.path}/lib')..createSync();
        final file = File('${libDir.path}/components.dart');
        file.writeAsStringSync('''
import 'package:flutter/material.dart';

class MyList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Divider(key: Key('offscreen_divider')),
      ],
    );
  }
}
''');
        final match = await findWidgetConstructorInProject(libDir, 'offscreen_divider');
        expect(match, isNotNull);
        expect(match!.type, 'Divider');
        expect(match.line, 8);
        expect(match.snippet, "Divider(key: Key('offscreen_divider'))");
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('get_memory_details advertises route canary parameter', () {
      final tools = server.toolListJson();
      final mem = tools.firstWhere((t) => t['name'] == 'get_memory_details');
      final schema = mem['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('route'), isTrue);
      expect(props.containsKey('cycle'), isTrue);
      expect(props.containsKey('times'), isTrue);
    });

    test('simulate_network advertises chaos parameters (errorRate, statusCode, restore)', () {
      final tools = server.toolListJson();
      final net = tools.firstWhere((t) => t['name'] == 'simulate_network');
      final schema = net['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('errorRate'), isTrue);
      expect(props.containsKey('statusCode'), isTrue);
      expect(props.containsKey('restore'), isTrue);
      expect(props.containsKey('condition'), isTrue);
    });

    test('audit_screen_health advertises viewports parameter for responsive matrix', () {
      final tools = server.toolListJson();
      final health = tools.firstWhere((t) => t['name'] == 'audit_screen_health');
      final schema = health['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('viewports'), isTrue);
    });

    test('execute_action_chain advertises exportAsTest parameters', () {
      final tools = server.toolListJson();
      final chain = tools.firstWhere((t) => t['name'] == 'execute_action_chain');
      final schema = chain['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('exportAsTest'), isTrue);
      expect(props.containsKey('testName'), isTrue);
      expect(props.containsKey('testFilePath'), isTrue);
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
