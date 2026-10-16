import 'dart:io';

import 'package:fp_server/fp_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Freshness guards for the human-facing docs that describe the MCP surface.
///
/// Two failure modes this catches (task 08, step 15):
///  * a doc links to a hand-maintained file that no longer exists — the deleted
///    `TOOLS.md` was still referenced from several pages after it was removed,
///    and the reference is the generated `TOOLS.generated.md`;
///  * a doc repeats a tool count that has drifted from the registration.
///
/// The generator tests (`tools_doc_generated_test.dart`,
/// `guidance_generated_test.dart`) prove the generated files match their
/// sources; this proves the prose that points at them still does.
void main() {
  final packageRoot = Directory.current;
  final repoRoot = packageRoot.parent.parent;

  /// The published docs a contributor reads. `docs/tasks/` planning notes are
  /// deliberately out of scope: they describe future work, not the shipped
  /// surface.
  const curated = <String>[
    'CLAUDE.md',
    'CONTRIBUTING.md',
    'README.md',
    'RELEASING.md',
    'ROADMAP.md',
    'docs/AI_AGENTS.md',
    'docs/ARCHITECTURE.md',
    'docs/BEST_PRACTICES.md',
    'docs/INDEX.md',
    'docs/MCP_DEVELOPMENT.md',
    'docs/PLUGINS.md',
    'docs/SETUP.md',
    'docs/TROUBLESHOOTING.md',
    'docs/field-test-findings.md',
    'docs/security-review.md',
  ];

  group('every relative link in the published docs resolves', () {
    final link = RegExp(r'\]\(([^)]+)\)');

    for (final relative in curated) {
      test(relative, () {
        final file = File(p.join(repoRoot.path, relative));
        expect(file.existsSync(), isTrue, reason: '$relative is missing');
        final dir = p.dirname(file.path);
        final broken = <String>[];
        for (final match in link.allMatches(file.readAsStringSync())) {
          var target = match.group(1)!.trim();
          if (target.isEmpty ||
              target.startsWith('#') ||
              target.startsWith('/') ||
              target.startsWith('http://') ||
              target.startsWith('https://') ||
              target.startsWith('mailto:')) {
            continue;
          }
          target = target.split('#').first.split('?').first;
          if (target.isEmpty) continue;
          final resolved = p.normalize(p.join(dir, target));
          if (!File(resolved).existsSync() &&
              !Directory(resolved).existsSync()) {
            broken.add(match.group(1)!);
          }
        }
        expect(
          broken,
          isEmpty,
          reason:
              'link to a path that exists; the tool reference is the '
              'generated TOOLS.generated.md, not a hand-maintained TOOLS.md',
        );
      });
    }
  });

  test('the tool count stated in the docs matches the registration', () {
    final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    final count = server.registeredToolNames.length;

    void agrees(String relative, RegExp pattern) {
      final text = File(p.join(repoRoot.path, relative)).readAsStringSync();
      final match = pattern.firstMatch(text);
      expect(
        match,
        isNotNull,
        reason: 'expected a tool-count claim matching $pattern in $relative',
      );
      expect(
        int.parse(match!.group(1)!),
        count,
        reason:
            '$relative repeats a stale tool count; the registered count is '
            '$count and the reference is the generated TOOLS.generated.md',
      );
    }

    agrees('CLAUDE.md', RegExp(r'exposing (\d+) MCP tools'));
    agrees('README.md', RegExp(r'registrations\): (\d+) tools'));
    agrees(
      'packages/fp_server/README.md',
      RegExp(r'^(\d+) tools;', multiLine: true),
    );
    agrees('CONTRIBUTING.md', RegExp(r'(\d+) MCP tools'));
  });

  test(
    'ARCHITECTURE.md names real tool mixins and the generated inventory',
    () {
      final text = File(
        p.join(repoRoot.path, 'docs/ARCHITECTURE.md'),
      ).readAsStringSync();
      expect(text, contains('TOOLS.generated.md'));

      final mixins = RegExp(
        r'[a-z0-9_]+_tools\.dart',
      ).allMatches(text).map((m) => m.group(0)!).toSet();
      expect(mixins, isNotEmpty, reason: 'the mixin list was removed entirely');
      for (final mixin in mixins) {
        expect(
          File(p.join(packageRoot.path, 'lib/src/tools', mixin)).existsSync(),
          isTrue,
          reason:
              'docs/ARCHITECTURE.md names $mixin, which is not in '
              'lib/src/tools/ — update the list or the link to the generated '
              'inventory',
        );
      }
    },
  );
}
