import 'dart:convert';

import 'package:fp_server/fp_server.dart';
import 'package:fp_server/src/tool_list_bytes.dart';
import 'package:fp_server/src/tool_list_report.dart';
import 'package:fp_server/src/zero_code.dart';
import 'package:test/test.dart';

void main() {
  final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
  final all = server.registeredToolNames;
  final names = all.toSet();

  List<Map<String, dynamic>> listJson(Iterable<String> wanted) =>
      server.toolListJson(wanted);

  test('the shared measure is the legacy character count', () {
    // The old inline measure; if the two drift, the budgets stop meaning what
    // they say.
    final inline = listJson(all)
        .map((tool) => jsonEncode(tool..remove('annotations')).length)
        .fold(0, (a, b) => a + b);
    expect(toolListTotalChars(listJson(all)), inline);
  });

  test('characters, UTF-8 bytes and wire bytes are separate measures', () {
    // Arabic, an emoji and an accented label: all are non-ASCII, so a
    // character count undercounts the bytes that cross the wire. This is the
    // fixture task 00 asks for; it proves an encoding correction cannot
    // masquerade as tool growth.
    final tool = <String, dynamic>{
      'name': 'get_app_summary',
      'description': 'Résumé العربية 🚀 — café',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'label': {'type': 'string', 'description': 'naïve'},
        },
      },
      'annotations': {'readOnlyHint': true, 'destructiveHint': false},
    };
    expect(toolListChars(tool), lessThan(toolListUtf8Bytes(tool)));
    // The wire size includes the annotations, so it is never smaller than the
    // projection it contains.
    expect(toolListUtf8Bytes(tool), lessThan(toolListWireBytes(tool)));
    // The projection drops annotations; the wire object keeps them.
    expect(toolModelProjection(tool).containsKey('annotations'), isFalse);
    expect(tool.containsKey('annotations'), isTrue);
    // The estimate is derived from UTF-8 bytes, and is labelled an estimate.
    expect(
      toolListTokens(toolListUtf8Bytes(tool)),
      toolListUtf8Bytes(tool) ~/ 4,
    );
  });

  test('the totals sum their per-tool measure', () {
    final tools = listJson(all);
    expect(
      toolListTotalChars(tools),
      tools.fold(0, (sum, t) => sum + toolListChars(t)),
    );
    expect(
      toolListTotalUtf8Bytes(tools),
      tools.fold(0, (sum, t) => sum + toolListUtf8Bytes(t)),
    );
    expect(
      toolListTotalWireBytes(tools),
      tools.fold(0, (sum, t) => sum + toolListWireBytes(t)),
    );
  });

  test('every profile is a subset of all', () {
    for (final profile in AppProfile.values) {
      expect(
        names.containsAll(profileToolNames(profile, all)),
        isTrue,
        reason: profile.id,
      );
    }
  });

  test('the profiles nest the way the visibility rule does', () {
    Set<String> of(AppProfile profile) =>
        profileToolNames(profile, all).toSet();
    expect(of(AppProfile.sdkDio), containsAll(of(AppProfile.sdkNoPlugins)));
    expect(of(AppProfile.sdkLabShop), containsAll(of(AppProfile.sdkDio)));
    expect(
      of(AppProfile.sdkLabNotes),
      containsAll(of(AppProfile.sdkNoPlugins)),
    );
    // The two lab apps carry different plugins, so neither contains the other.
    expect(
      of(AppProfile.sdkLabShop).containsAll(of(AppProfile.sdkLabNotes)),
      isFalse,
    );
    expect(
      of(AppProfile.sdkLabNotes).containsAll(of(AppProfile.sdkLabShop)),
      isFalse,
    );
    // profile_build is sdk_lab_shop without the debug-only tools.
    expect(
      of(AppProfile.profileBuild),
      of(
        AppProfile.sdkLabShop,
      ).difference({'hot_reload', 'generate_test', 'scenario'}),
    );
  });

  test('zero_code is exactly zeroCodeTools', () {
    expect(profileToolNames(AppProfile.zeroCode, all).toSet(), zeroCodeTools);
  });

  test(
    'a plugin profile lists that plugin\'s tools and no other plugin\'s',
    () {
      final shop = profileToolNames(AppProfile.sdkLabShop, all).toSet();
      final notes = profileToolNames(AppProfile.sdkLabNotes, all).toSet();
      final none = profileToolNames(AppProfile.sdkNoPlugins, all).toSet();
      for (final tool in [
        'get_network_logs',
        'simulate_network',
        'exec_sql_query',
        'get_state',
      ]) {
        expect(shop, contains(tool), reason: tool);
        expect(none, isNot(contains(tool)), reason: tool);
      }
      for (final tool in [
        'get_hive_contents',
        'exec_sql_query',
        'get_state',
        'get_connectivity',
      ]) {
        expect(notes, contains(tool), reason: tool);
      }
      expect(notes, isNot(contains('get_network_logs')));
      expect(shop, isNot(contains('get_hive_contents')));
    },
  );

  test('the profile costs match the budget test\'s numbers', () {
    int chars(AppProfile profile) =>
        profileCost(profile, all, server.toolListJson).chars;
    expect(chars(AppProfile.all), lessThanOrEqualTo(41300));
    expect(chars(AppProfile.sdkNoPlugins), lessThanOrEqualTo(29500));
    expect(chars(AppProfile.zeroCode), lessThanOrEqualTo(9700));
  });

  test('a profile cost adds up and is sorted by size', () {
    final cost = profileCost(AppProfile.sdkLabShop, all, server.toolListJson);
    expect(cost.tools, cost.perTool.length);
    expect(cost.chars, cost.perTool.fold(0, (sum, t) => sum + t.chars));
    expect(cost.utf8Bytes, cost.perTool.fold(0, (sum, t) => sum + t.utf8Bytes));
    expect(cost.wireBytes, cost.perTool.fold(0, (sum, t) => sum + t.wireBytes));
    // UTF-8 bytes are never fewer than characters: descriptions are ASCII
    // today, so the two are equal, but the invariant must hold either way.
    expect(cost.utf8Bytes, greaterThanOrEqualTo(cost.chars));
    expect(cost.wireBytes, greaterThanOrEqualTo(cost.utf8Bytes));
    expect(cost.tokens, cost.utf8Bytes ~/ 4);
    for (var i = 1; i < cost.perTool.length; i++) {
      expect(
        cost.perTool[i - 1].chars,
        greaterThanOrEqualTo(cost.perTool[i].chars),
      );
    }
  });
}
