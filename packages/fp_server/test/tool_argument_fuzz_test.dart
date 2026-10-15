import 'package:fp_server/fp_server.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

/// Fuzzes every registered tool's arguments (task 02 §D): a malformed call
/// must come back as a refusal that says what was wrong — never a cast error
/// deep in a tool, which an agent reads as "the app is busy, retry" — and a
/// value that is only stringified must be accepted.
///
/// This is the path a nested call takes: `execute_action_chain`,
/// `profile_action`, `run_on_devices` and the leak `cycle` run other tools
/// through `_toolCallbacks`, which is this gate and then the tool, with no
/// transport. A direct `tools/call` is validated by mcp_dart against the same
/// schema before it reaches here (a stringified value is refused there with
/// `-32602 Invalid arguments`); see the PR for the bridge evidence.
void main() {
  final server = FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');
  final names = server.registeredToolNames.toList()..sort();

  test('has tools to fuzz, including the list-all set', () {
    expect(names, isNotEmpty);
    expect(names, contains('get_app_summary'));
    expect(names, contains('execute_action_chain'));
    expect(names, contains('launch_app'));
  });

  test('a tool that needs no arguments answers without an app', () async {
    final result = await server
        .callToolForTest('get_app_summary', const {})
        .timeout(const Duration(seconds: 10));
    expect(_textOf(result), isNotEmpty);
  });

  for (final name in names) {
    final schema =
        server.toolListJson([name]).single['inputSchema'] as Map? ??
        const <String, dynamic>{};
    final properties =
        (schema['properties'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final required =
        (schema['required'] as List?)?.cast<String>() ?? const <String>[];

    Map<String, dynamic> minimalArgs() => {
      for (final key in required) key: _minimal(properties[key]),
    };

    group(name, () {
      test('refuses a missing required argument by name', () async {
        if (required.isEmpty) return;
        final problem = server.checkArgumentsForTest(name, const {});
        expect(problem, isNotNull);
        expect(problem, contains(required.first));
        expect(problem, contains('nothing was done'));
        await _expectCleanRefusal(server, name, const {});
      });

      test('refuses a null required argument', () {
        if (required.isEmpty) return;
        final args = minimalArgs()..[required.first] = null;
        final problem = server.checkArgumentsForTest(name, args);
        expect(problem, isNotNull);
        expect(problem, contains(required.first));
      });

      test('refuses the wrong type for every argument', () async {
        for (final entry in properties.entries) {
          // A property whose schema declares no type takes any JSON, so there
          // is no wrong type for it.
          if (_kind(entry.value) == 'any') continue;
          final args = minimalArgs()..[entry.key] = _wrong(entry.value);
          final problem = server.checkArgumentsForTest(name, args);
          expect(problem, isNotNull, reason: '$name.${entry.key}');
          expect(
            problem,
            contains('nothing was done'),
            reason: '$name.${entry.key}',
          );
          // A refusal must not tell the agent to retry the same broken call.
          expect(
            problem,
            isNot(contains('retry')),
            reason: '$name.${entry.key}',
          );
          await _expectCleanRefusal(server, name, args);
        }
      });

      test('accepts a stringified value where the schema allows', () {
        for (final entry in properties.entries) {
          if (_kind(entry.value) == 'any') continue;
          final args = minimalArgs()..[entry.key] = _stringified(entry.value);
          expect(
            server.checkArgumentsForTest(name, args),
            isNull,
            reason: '$name.${entry.key}',
          );
        }
      });

      test('refuses an unknown extra argument', () async {
        final args = minimalArgs()..['__nope__'] = 1;
        final problem = server.checkArgumentsForTest(name, args);
        expect(problem, isNotNull);
        expect(problem, contains('__nope__'));
        await _expectCleanRefusal(server, name, args);
      });
    });
  }
}

/// Calls [name] with [args] through the full wrapper and checks it comes back
/// as an error result rather than an exception or a raw cast failure.
///
/// Only calls when the argument gate already refused: a tool that got this far
/// (a bug, reported by the caller's `expect`) could start a build.
Future<void> _expectCleanRefusal(
  FlutterPilotServer server,
  String name,
  Map<String, dynamic> args,
) async {
  if (server.checkArgumentsForTest(name, args) == null) return;
  final result = await server
      .callToolForTest(name, args)
      .timeout(const Duration(seconds: 10));
  expect(result.isError, isTrue, reason: name);
  final text = _textOf(result);
  for (final marker in const [
    'is not a subtype of',
    "type '",
    'NoSuchMethodError',
    'Null check operator',
    'retry',
  ]) {
    expect(text, isNot(contains(marker)), reason: '$name: $text');
  }
}

String _textOf(CallToolResult result) => [
  for (final part in result.content)
    if (part is TextContent) part.text,
].join('\n');

/// The schema's kind for a property, with `enum` taking precedence over the
/// `string` type the enum sits on.
String _kind(Object? schema) {
  final map = schema as Map?;
  final values = map?['enum'];
  if (values is List && values.isNotEmpty) return 'enum';
  final type = map?['type'];
  return type is String ? type : 'any';
}

/// The smallest value the schema accepts, for the arguments a case does not
/// touch.
Object? _minimal(Object? schema) => switch (_kind(schema)) {
  'any' => 'x',
  'integer' => 1,
  'number' => 1.5,
  'boolean' => true,
  'array' => const <Object?>[],
  'object' => const <String, dynamic>{},
  'enum' => ((schema as Map)['enum'] as List).first,
  _ => 'x',
};

/// A value of the wrong type for the schema.
Object? _wrong(Object? schema) => switch (_kind(schema)) {
  'integer' || 'number' => 'abc',
  'boolean' => 'yes',
  'array' => const <String, dynamic>{},
  'object' => const <Object?>[],
  'enum' => '__not_a_value__',
  _ => const <Object?>[],
};

/// The value in the shape a client sends when it stringifies everything.
Object? _stringified(Object? schema) => switch (_kind(schema)) {
  'integer' => '5',
  'number' => '1.5',
  'boolean' => 'true',
  'array' => '[]',
  'object' => '{}',
  'enum' => '${((schema as Map)['enum'] as List).first}'.toUpperCase(),
  _ => 5,
};
