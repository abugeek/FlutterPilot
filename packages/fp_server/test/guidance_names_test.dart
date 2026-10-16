import 'dart:io';

import 'package:fp_server/fp_server.dart';
import 'package:fp_server/src/param_aliases.dart';
import 'package:fp_server/src/retired_tools.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every tool name and `tool(argument: ...)` the agent-facing text mentions
/// must exist. This is what makes several guidance texts per audience safe: a
/// merged or renamed tool cannot stay behind in a doc, a skill or the server
/// instructions (task 05; task 04 renamed tools, and this is what catches the
/// mentions it missed).
///
/// Scanned: `serverInstructions`, the `flutterpilot_guide` prompt, every tool
/// description and property description, `CLAUDE.md`, `README.md`,
/// `docs/*.md`, `skills/flutterpilot/SKILL.md`. Not scanned: histories that
/// may name what a tool was called at the time (`docs/field-test-findings.md`,
/// `ROADMAP.md`).
void main() {
  final repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));

  final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
  final tools = server.registeredToolNames.toSet();

  /// Tool name -> the arguments its schema accepts.
  final schema = <String, Set<String>>{
    for (final tool in server.toolListJson())
      tool['name'] as String: {
        ...?((tool['inputSchema'] as Map?)?['properties'] as Map?)?.keys
            .cast<String>(),
      },
  };

  /// Why [name] is not a tool, or null when it is one (or is not a tool at
  /// all: pubspec sections, MCP client config keys, and the packages around
  /// the server have no tool named after them).
  String? notATool(String name, String at) {
    if (tools.contains(name) ||
        _notTools.contains(name) ||
        name.startsWith('flutterpilot_')) {
      return null;
    }
    // A merged tool: say which tool it became, so the fix is obvious.
    final retired = retiredTools[name];
    if (retired != null) {
      return '$at: "$name" was merged into ${retired.tool}; update the text';
    }
    return '$at: "$name" is not a registered tool (merged or renamed? see '
        'TOOLS.generated.md)';
  }

  /// Why [tool] does not take [arg], or null when it does.
  String? noSuchArgument(String tool, String arg, String at) {
    final accepted = schema[tool];
    if (accepted == null || accepted.contains(arg)) return null;
    // An alias the server canonicalizes to a schema name (key/target, ...).
    final canonical = normalizeToolParams({arg: 'x'}).keys.toSet()..remove(arg);
    if (canonical.any(accepted.contains)) return null;
    return '$at: $tool has no "$arg"; it takes '
        '${(accepted.toList()..sort()).join(', ')}';
  }

  Map<String, String> sources() {
    final sources = <String, String>{
      'serverInstructions': serverInstructions,
      'the flutterpilot_guide prompt': guidePrompt,
    };
    void add(String relative) {
      final file = File(p.join(repoRoot, relative));
      if (file.existsSync()) {
        sources[relative] = file.readAsStringSync().replaceAll('\r\n', '\n');
      }
    }

    add('CLAUDE.md');
    add('README.md');
    add('skills/flutterpilot/SKILL.md');
    // The landing page shows real calls and is user-facing too. Strip the tags
    // so attributes and class names are not read as prose.
    final site = File(p.join(repoRoot, 'site/index.html'));
    if (site.existsSync()) {
      sources['site/index.html'] = site
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .replaceAll(RegExp(r'<[^>]*>'), ' ');
    }
    for (final file in Directory(
      p.join(repoRoot, 'docs'),
    ).listSync().whereType<File>()) {
      final name = p.basename(file.path);
      // History: it records what the tools were called at the time.
      if (!name.endsWith('.md') || name == 'field-test-findings.md') continue;
      add('docs/$name');
    }
    return sources;
  }

  test('every tool name in the agent-facing text exists', () {
    final problems = <String>{};
    sources().forEach((where, text) {
      void check(RegExp pattern, {bool withArgs = false, int argGroup = 2}) {
        for (final match in pattern.allMatches(text)) {
          final name = match[1]!;
          final at = '$where:${_lineOf(text, match.start)}';
          final bad = notATool(name, at);
          if (bad != null) problems.add(bad);
          if (!withArgs || bad != null) continue;
          // Values may hold colons (URLs, labels): drop quoted strings first.
          final bare = match
              .group(argGroup)!
              .replaceAll(RegExp('"[^"]*"|\'[^\']*\''), ' X ');
          for (final arg in RegExp(
            '([A-Za-z][A-Za-z0-9_]*)\\s*:',
          ).allMatches(bare)) {
            final noArg = noSuchArgument(name, arg[1]!, at);
            if (noArg != null) problems.add(noArg);
          }
        }
      }

      // `tool_name` in inline code.
      check(RegExp(r'`([a-z][a-z0-9]*(?:_[a-z0-9]+)+)`'));
      // `tool_name(argument: ...)` in inline code (no nested object/array).
      check(
        RegExp(r'`([a-z][a-z0-9]*(?:_[a-z0-9]+)+)\(([^`{}\[\]\n]{0,90})\)`'),
        withArgs: true,
      );
      // tool_name( outside inline code: a code comment or a prose call.
      // Not preceded by a word character or a dot, so `pub.get(` and
      // `dart.io(` are not read as tool names.
      check(RegExp(r'(?<![\w.])([a-z][a-z0-9]*(?:_[a-z0-9]+)+)\('));
      // call_tool("tool_name" in a skill example.
      check(RegExp(r'call_tool\("([a-z][a-z0-9_]+)"'));
      // The keys of call_tool("tool_name", {...}) up to the first nested
      // value (the keys inside a `states`/`fields`/`steps` value are that
      // value's, not the tool's).
      final open = RegExp(r'call_tool\("([a-z0-9_]+)"\s*,\s*\{');
      for (final example in open.allMatches(text)) {
        final rest = text.substring(example.end);
        final cut = rest.indexOf(RegExp(r'[{}[]'));
        final head = cut < 0 ? rest : rest.substring(0, cut);
        final at = '$where:${_lineOf(text, example.start)}';
        for (final arg in RegExp(
          r'"([A-Za-z][A-Za-z0-9_]*)"\s*:',
        ).allMatches(head)) {
          final noArg = noSuchArgument(example[1]!, arg[1]!, at);
          if (noArg != null) problems.add(noArg);
        }
      }
    });
    expect(problems, isEmpty, reason: 'Fix the text:\n${problems.join('\n')}');
  });

  test('every tool a description names exists', () {
    final problems = <String>[];
    for (final tool in server.toolListJson()) {
      final name = tool['name'] as String;
      final text = [
        tool['description'] ?? '',
        _propertyDescriptions(tool),
      ].join('\n');
      for (final match in RegExp(
        r'`([a-z][a-z0-9]*(?:_[a-z0-9]+)+)`',
      ).allMatches(text)) {
        final bad = notATool(match[1]!, 'the description of $name');
        if (bad != null) problems.add(bad);
      }
    }
    expect(problems, isEmpty, reason: 'Fix the text:\n${problems.join('\n')}');
  });

  test('the shipped guidance texts stay within their size budget', () {
    // serverInstructions reaches the model in every session, so its budget
    // lives with the other tool budgets (tool_registration_test.dart, 1200,
    // unchanged: the generated text is byte-identical to the hand-written one).
    // These two are fetched on demand. 4413 and 4002 when written (2026-10-14).
    expect(guidePrompt.length, lessThanOrEqualTo(4855));
    final skill = File(
      p.join(repoRoot, 'skills/flutterpilot/SKILL.md'),
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(skill.length, lessThanOrEqualTo(4403));
  });
}

String _propertyDescriptions(Map<String, dynamic> tool) => [
  for (final property
      in ((tool['inputSchema'] as Map?)?['properties'] as Map? ?? const {})
          .values)
    (property as Map)['description'] ?? '',
].join('\n');

int _lineOf(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length + 1;

/// Snake_case words that look like tool names but are not, with the reason.
const _notTools = {
  'dev_dependencies', // pubspec.yaml section.
  'context_servers', // Zed's key for MCP servers.
  'call_tool', // How a skill example calls a tool; not a tool itself.
  // Curated MCP prompt names (task 17): fetched with `prompts/get`.
  'debug_layout_overflow',
  'diagnose_exception',
  'create_integration_test',
  'audit_screen_health',
  // The packages around the server (task 31 renamed them to fp_*): a pubspec
  // name in the docs, not a tool. Update this list when a package is added,
  // renamed or removed.
  'fp_sdk',
  'fp_server',
  'fp_cli',
  'fp_riverpod',
  'fp_bloc',
  'fp_dio',
  'fp_drift',
  'fp_sqflite',
  'fp_hive',
  'fp_shared_preferences',
  'fp_supabase',
  'fp_gorouter',
  'fp_connectivity',
  'fp_firebase',
  'fp_secure_storage',
  // The fictitious plugin PLUGINS.md teaches you to write.
  'fp_mylib',
};
