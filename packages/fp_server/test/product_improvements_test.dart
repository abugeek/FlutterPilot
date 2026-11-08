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

    test('navigate_to advertises pathParams and queryParams for dynamic routing', () {
      final tools = server.toolListJson();
      final nav = tools.firstWhere((t) => t['name'] == 'navigate_to');
      final schema = nav['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('pathParams'), isTrue);
      expect(props.containsKey('queryParams'), isTrue);
      expect(props.containsKey('deepLink'), isTrue);
    });

    test('enter_text advertises submit and waitFor parameters', () {
      final tools = server.toolListJson();
      final enterText = tools.firstWhere((t) => t['name'] == 'enter_text');
      final schema = enterText['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('submit'), isTrue);
      expect(props.containsKey('waitFor'), isTrue);
      expect(props.containsKey('timeoutMs'), isTrue);
    });

    test('fill_form advertises waitFor and timeoutMs parameters', () {
      final tools = server.toolListJson();
      final fillForm = tools.firstWhere((t) => t['name'] == 'fill_form');
      final schema = fillForm['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('waitFor'), isTrue);
      expect(props.containsKey('timeoutMs'), isTrue);
    });

    test('get_interactive_elements advertises collapse parameter', () {
      final tools = server.toolListJson();
      final elementsTool =
          tools.firstWhere((t) => t['name'] == 'get_interactive_elements');
      final schema = elementsTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('collapse'), isTrue);
    });

    test('assert_widget advertises asserts batch parameter', () {
      final tools = server.toolListJson();
      final assertTool = tools.firstWhere((t) => t['name'] == 'assert_widget');
      final schema = assertTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('asserts'), isTrue);
      expect(props['asserts']['type'], 'array');
    });

    test('get_widget_tree advertises collapse and subtree parameters', () {
      final tools = server.toolListJson();
      final treeTool = tools.firstWhere((t) => t['name'] == 'get_widget_tree');
      final schema = treeTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('collapse'), isTrue);
      expect(props.containsKey('subtree'), isTrue);
    });

    test('get_network_logs advertises query, errorsOnly, and limit parameters', () {
      final tools = server.toolListJson();
      final netTool = tools.firstWhere((t) => t['name'] == 'get_network_logs');
      final schema = netTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('query'), isTrue);
      expect(props.containsKey('errorsOnly'), isTrue);
      expect(props.containsKey('limit'), isTrue);
    });

    test('get_http_profile advertises query, method, and errorsOnly parameters', () {
      final tools = server.toolListJson();
      final httpTool = tools.firstWhere((t) => t['name'] == 'get_http_profile');
      final schema = httpTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('query'), isTrue);
      expect(props.containsKey('method'), isTrue);
      expect(props.containsKey('errorsOnly'), isTrue);
    });

    test('hot_reload advertises waitForSettled parameter', () {
      final tools = server.toolListJson();
      final reloadTool = tools.firstWhere((t) => t['name'] == 'hot_reload');
      final schema = reloadTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('waitForSettled'), isTrue);
    });

    test('get_memory_details advertises diffBaseline and resetBaseline parameters', () {
      final tools = server.toolListJson();
      final memTool = tools.firstWhere((t) => t['name'] == 'get_memory_details');
      final schema = memTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('diffBaseline'), isTrue);
      expect(props.containsKey('resetBaseline'), isTrue);
    });

    test('scroll_into_view advertises tap and waitFor parameters', () {
      final tools = server.toolListJson();
      final scrollTool = tools.firstWhere((t) => t['name'] == 'scroll_into_view');
      final schema = scrollTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('tap'), isTrue);
      expect(props['tap']['type'], 'boolean');
      expect(props.containsKey('waitFor'), isTrue);
    });

    test('get_shared_preferences advertises key and query parameters', () {
      final tools = server.toolListJson();
      final prefsTool = tools.firstWhere((t) => t['name'] == 'get_shared_preferences');
      final schema = prefsTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('key'), isTrue);
      expect(props.containsKey('query'), isTrue);
    });

    test('get_secure_storage advertises query parameter', () {
      final tools = server.toolListJson();
      final secTool = tools.firstWhere((t) => t['name'] == 'get_secure_storage');
      final schema = secTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('query'), isTrue);
      expect(props.containsKey('key'), isTrue);
    });

    test('verify_feature advertises asserts and assert parameters', () {
      final tools = server.toolListJson();
      final vfTool = tools.firstWhere((t) => t['name'] == 'verify_feature');
      final schema = vfTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('asserts'), isTrue);
      expect(props['asserts']['type'], 'array');
      expect(props.containsKey('assert'), isTrue);
      expect(props['assert']['type'], 'object');
    });

    test('press_key advertises count, waitFor, and timeoutMs parameters', () {
      final tools = server.toolListJson();
      final pkTool = tools.firstWhere((t) => t['name'] == 'press_key');
      final schema = pkTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('count'), isTrue);
      expect(props['count']['type'], 'integer');
      expect(props.containsKey('waitFor'), isTrue);
      expect(props.containsKey('timeoutMs'), isTrue);
    });

    test('toggle_checkbox advertises value, waitFor, and timeoutMs parameters', () {
      final tools = server.toolListJson();
      final tcTool = tools.firstWhere((t) => t['name'] == 'toggle_checkbox');
      final schema = tcTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('value'), isTrue);
      expect(props['value']['type'], 'boolean');
      expect(props.containsKey('waitFor'), isTrue);
      expect(props.containsKey('timeoutMs'), isTrue);
    });

    test('wait_for advertises anyOf and failureKey parameters', () {
      final tools = server.toolListJson();
      final wfTool = tools.firstWhere((t) => t['name'] == 'wait_for');
      final schema = wfTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('anyOf'), isTrue);
      expect(props['anyOf']['type'], 'array');
      expect(props.containsKey('failureKey'), isTrue);
      expect(props['failureKey']['type'], 'string');
    });

    test('compare_screenshot advertises key parameter for component cropping', () {
      final tools = server.toolListJson();
      final csTool = tools.firstWhere((t) => t['name'] == 'compare_screenshot');
      final schema = csTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('key'), isTrue);
      expect(props['key']['type'], 'string');
    });

    test('capture_screenshot advertises key parameter for element cropping', () {
      final tools = server.toolListJson();
      final csTool = tools.firstWhere((t) => t['name'] == 'capture_screenshot');
      final schema = csTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('key'), isTrue);
      expect(props['key']['type'], 'string');
    });

    test('inspect_widget advertises properties parameter', () {
      final tools = server.toolListJson();
      final iwTool = tools.firstWhere((t) => t['name'] == 'inspect_widget');
      final schema = iwTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('properties'), isTrue);
      expect(props['properties']['type'], 'boolean');
    });

    test('get_semantics_tree advertises query parameter', () {
      final tools = server.toolListJson();
      final stTool = tools.firstWhere((t) => t['name'] == 'get_semantics_tree');
      final schema = stTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('query'), isTrue);
      expect(props['query']['type'], 'string');
    });

    test('gesture_widget advertises waitFor and timeoutMs parameters', () {
      final tools = server.toolListJson();
      final gwTool = tools.firstWhere((t) => t['name'] == 'gesture_widget');
      final schema = gwTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('waitFor'), isTrue);
      expect(props.containsKey('timeoutMs'), isTrue);
    });

    test('get_hive_contents advertises box and query parameters', () {
      final tools = server.toolListJson();
      final ghTool = tools.firstWhere((t) => t['name'] == 'get_hive_contents');
      final schema = ghTool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('box'), isTrue);
      expect(props.containsKey('query'), isTrue);
    });

    test('get_interactive_elements advertises query parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'get_interactive_elements');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('query'), isTrue);
      expect(props['query']['type'], 'string');
    });

    test('get_widget_properties advertises keys parameter for batching', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'get_widget_properties');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('keys'), isTrue);
      expect(props['keys']['type'], 'array');
    });

    test('get_debug_logs advertises waitFor and timeoutMs parameters', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'get_debug_logs');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('waitFor'), isTrue);
      expect(props.containsKey('timeoutMs'), isTrue);
    });

    test('exec_sql_query advertises query and limit parameters', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'exec_sql_query');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('query'), isTrue);
      expect(props.containsKey('limit'), isTrue);
    });

    test('get_errors advertises clear parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'get_errors');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('clear'), isTrue);
      expect(props['clear']['type'], 'boolean');
    });

    test('apply_and_verify advertises waitFor parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'apply_and_verify');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('waitFor'), isTrue);
      expect(props['waitFor']['type'], 'string');
    });

    test('audit_screen_health advertises category parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'audit_screen_health');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('category'), isTrue);
    });

    test('replay_flow advertises assertWidget parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'replay_flow');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('assertWidget'), isTrue);
    });

    test('audit_design_tokens advertises type parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'audit_design_tokens');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('type'), isTrue);
    });

    test('get_navigation_stack advertises waitForRoute parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'get_navigation_stack');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('waitForRoute'), isTrue);
      expect(props['waitForRoute']['type'], 'string');
    });

    test('profile_frame_budget advertises reset parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'profile_frame_budget');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('reset'), isTrue);
      expect(props['reset']['type'], 'boolean');
    });

    test('set_app_settings advertises reset parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'set_app_settings');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('reset'), isTrue);
      expect(props['reset']['type'], 'boolean');
    });

    test('apply_patch_and_verify advertises waitFor parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'apply_patch_and_verify');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('waitFor'), isTrue);
      expect(props['waitFor']['type'], 'string');
    });

    test('get_connectivity advertises waitForStatus parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'get_connectivity');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('waitForStatus'), isTrue);
      expect(props['waitForStatus']['type'], 'string');
    });

    test('mock_http_response advertises mocks batch parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'mock_http_response');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('mocks'), isTrue);
      expect(props['mocks']['type'], 'array');
    });

    test('simulate_viewport_matrix advertises viewports parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'simulate_viewport_matrix');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('viewports'), isTrue);
      expect(props['viewports']['type'], 'array');
    });

    test('native_describe_screen advertises query parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'native_describe_screen');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('query'), isTrue);
      expect(props['query']['type'], 'string');
    });

    test('crawl_app advertises audit parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'crawl_app');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('audit'), isTrue);
      expect(props['audit']['type'], 'boolean');
    });

    test('replay_flow advertises exportAsTest and testName parameters', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'replay_flow');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('exportAsTest'), isTrue);
      expect(props['exportAsTest']['type'], 'boolean');
      expect(props.containsKey('testName'), isTrue);
      expect(props['testName']['type'], 'string');
    });

    test('query_firestore advertises query parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'query_firestore');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('query'), isTrue);
      expect(props['query']['type'], 'string');
    });

    test('query_supabase_table advertises query parameter', () {
      final tools = server.toolListJson();
      final tool = tools.firstWhere((t) => t['name'] == 'query_supabase_table');
      final schema = tool['inputSchema'] as Map;
      final props = schema['properties'] as Map;
      expect(props.containsKey('query'), isTrue);
      expect(props['query']['type'], 'string');
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
