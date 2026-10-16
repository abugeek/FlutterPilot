// Task 07 gated substep: the public `outputSchema` pilot.
//
// The spec (§11–12) allows advertising schemas only on one or two small stable
// families, after testing every variant and SDK behavior, and requires the
// per-profile cost to be measured. Advertisement is therefore opt-in
// (`advertiseOutputSchemas` / `--output-schemas`) and off by default: no client
// here can demonstrate the benefit §11 requires before it is turned on. These
// tests prove the mechanism is correct and measure exactly what it costs, so a
// later evaluation with a real client can flip one flag.
import 'package:fp_server/fp_server.dart';
import 'package:fp_server/src/structured_results.dart';
import 'package:fp_server/src/tool_list_bytes.dart';
import 'package:fp_server/src/tool_profiles.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'support/in_process_mcp_client.dart';

/// One payload per documented variant of the two pilot families, built with the
/// real builders (the same ones the handlers use).
Map<String, List<Map<String, dynamic>>> pilotVariants() => {
  'audit_screen_health': [
    // one screen, clean.
    auditVerdict(
      requested: 0,
      visited: 0,
      audited: 1,
      failed: 0,
      skipped: 0,
      findings: const {'overflows': 2},
      restored: true,
      incomplete: false,
      loading: false,
    ),
    // partial sweep.
    auditVerdict(
      requested: 41,
      visited: 38,
      audited: 37,
      failed: 3,
      skipped: 1,
      findings: const {},
      restored: false,
      incomplete: true,
      loading: true,
      status: 'partial',
    ),
    // could not evaluate.
    auditVerdict(
      requested: 0,
      visited: 0,
      audited: 0,
      failed: 1,
      skipped: 0,
      findings: const {},
      restored: true,
      incomplete: true,
      loading: false,
      status: 'unavailable',
      reason: 'no app',
    ),
  ],
  'navigate_to': [
    navigationVerdict(
      requested: '/home',
      current: '/home',
      waitRequired: false,
      completed: true,
    ),
    navigationVerdict(
      requested: '/home',
      waitRequired: true,
      waitStatus: 'missing',
      completed: false,
      uncertain: true,
    ),
    navigationVerdict(
      requested: '/home',
      waitRequired: false,
      completed: false,
      uncertain: true,
      status: 'unavailable',
    ),
  ],
};

void main() {
  group('StructuredSpec.toJsonSchema', () {
    test('renders objects, lists, enums and required fields', () {
      final spec = StructuredSpec.object({
        'kind': StructuredField(
          StructuredSpec.string(oneOf: {'b', 'a'}),
          required: true,
        ),
        'n': StructuredField(StructuredSpec.integer(), required: true),
        'items': StructuredField(StructuredSpec.list(StructuredSpec.boolean())),
      });
      expect(spec.toJsonSchema(), {
        'type': 'object',
        'properties': {
          'kind': {
            'type': 'string',
            'enum': ['a', 'b'],
          },
          'n': {'type': 'integer'},
          'items': {
            'type': 'array',
            'items': {'type': 'boolean'},
          },
        },
        'required': ['kind', 'n'],
        'additionalProperties': false,
      });
    });

    test('omits `required` when nothing is required', () {
      final spec = StructuredSpec.object({
        'a': StructuredField(StructuredSpec.string()),
      });
      expect(spec.toJsonSchema(), isNot(contains('required')));
    });
  });

  test('the pilot families are registered tools with contracts', () {
    final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    expect(structuredOutputSchemas.keys.toSet(), outputSchemaPilotFamilies);
    for (final name in outputSchemaPilotFamilies) {
      expect(server.registeredToolNames, contains(name), reason: name);
      expect(structuredContracts, contains(name), reason: name);
      expect(structuredOutputSchemas[name], isNotNull, reason: name);
    }
  });

  test('advertisement is opt-in and pilot-only', () {
    final off = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
    for (final tool in off.toolListJson()) {
      expect(tool['outputSchema'], isNull, reason: '${tool['name']}');
    }

    final on = FlutterPilotServer(
      vmServiceUri: 'ws://localhost:8888',
      staticTools: true,
      advertiseOutputSchemas: true,
    );
    final advertised = {
      for (final tool in on.toolListJson())
        if (tool['outputSchema'] != null) tool['name'] as String,
    };
    expect(advertised, outputSchemaPilotFamilies);
    for (final name in advertised) {
      expect(
        on.toolListJson().firstWhere((t) => t['name'] == name)['outputSchema'],
        structuredOutputSchemas[name],
      );
    }
  });

  test('advertising grows the client wire list, not the model projection', () {
    // The per-profile budgets measure the model-facing projection
    // (name/description/inputSchema only), so they cannot see `outputSchema`;
    // the client that forwards the whole tool object does pay for it.
    // Measured 2026-10-16: projection 40 737 chars either way, wire
    // 47 374 -> 48 630 B (+1 256 B) for both pilot schemas.
    int projection(FlutterPilotServer s) =>
        toolListTotalChars(s.toolListJson());
    int wire(FlutterPilotServer s) => toolListTotalWireBytes(s.toolListJson());
    FlutterPilotServer build({
      required bool advertise,
      ToolProfile profile = ToolProfile.all,
    }) => FlutterPilotServer(
      vmServiceUri: 'ws://localhost:8888',
      staticTools: true,
      toolProfile: profile,
      advertiseOutputSchemas: advertise,
    );

    for (final profile in ToolProfile.values) {
      final off = build(advertise: false, profile: profile);
      final on = build(advertise: true, profile: profile);
      expect(
        projection(on),
        projection(off),
        reason: 'the measured budgets must not move (${profile.name})',
      );
      expect(
        wire(on) - wire(off),
        greaterThan(0),
        reason:
            'the client wire list must show the two schemas '
            '(${profile.name})',
      );
    }
  });

  test('every documented pilot variant satisfies contract and schema', () {
    final variants = pilotVariants();
    expect(variants.keys.toSet(), outputSchemaPilotFamilies);
    for (final name in outputSchemaPilotFamilies) {
      final schema = JsonObject.fromJson(structuredOutputSchemas[name]!);
      final payloads = variants[name]!;
      expect(payloads, isNotEmpty, reason: name);
      for (final payload in payloads) {
        // Developer-side contract...
        expect(structuredProblems(name, payload), isEmpty, reason: name);
        // ...and the exact schema the SDK would validate at the wire.
        expect(
          () => schema.validate(payload),
          returnsNormally,
          reason: '$name: $payload',
        );
      }
    }
  });

  test(
    'a real client round-trip advertises and enforces the pilot schemas',
    () async {
      final server = FlutterPilotServer(
        callLog: false,
        staticTools: true,
        advertiseOutputSchemas: true,
      );
      addTearDown(server.stop);
      final client = InProcessMcpClient();
      addTearDown(client.close);

      // No projectRoot: discovery finds nothing, so the app-scoped call is an
      // error result — which the SDK exempts from output validation, exactly as
      // it must for a refusal/unavailable path.
      await server.start(transport: client.transport);
      await client.initialize();
      final tools = await client.request('tools/list');
      final listed = {
        for (final tool
            in ((tools['result'] as Map)['tools'] as List)
                .cast<Map<String, dynamic>>())
          tool['name'] as String: tool,
      };
      for (final name in outputSchemaPilotFamilies) {
        expect(listed[name]!['outputSchema'], structuredOutputSchemas[name]);
      }
      expect(
        listed.keys.where((n) => listed[n]!['outputSchema'] != null).toSet(),
        outputSchemaPilotFamilies,
      );

      // The unavailable path still answers (an error result), and still carries
      // the structured twin the contract promises.
      final call = await client.callTool('navigate_to', {'route': '/home'});
      expect((call['result'] as Map)['isError'], isTrue);
      expect(InProcessMcpClient.structuredOf(call), isNotNull);
      expect(
        structuredProblems(
          'navigate_to',
          InProcessMcpClient.structuredOf(call)!,
        ),
        isEmpty,
      );
    },
  );
}
