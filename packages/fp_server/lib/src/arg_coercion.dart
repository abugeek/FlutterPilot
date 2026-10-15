import 'dart:convert';

/// What a tool's `inputSchema` expects of one argument (task 02 §A).
///
/// MCP clients and models regularly send the right value in the wrong shape —
/// `"steps": "[{\"tool\":...}]"`, `"limit": "100"`, `"enabled": "true"`,
/// `"count": 3.0`, `"fields": "{\"Email\":\"a@b.c\"}"`. The schema says what
/// was meant, so bring the value to it before the tool callback runs; a cast
/// error deep inside a tool reads to an agent as "the app is busy, retry".
sealed class ArgType {
  const ArgType({this.example});

  /// The snippet shown in a refusal: the `e.g.` from the property's
  /// description, or null to generate one from the type and the argument name.
  final String? example;
}

/// A string; also accepts a number or a bool, stringified.
class ArgString extends ArgType {
  const ArgString({super.example});
}

/// An integer; also accepts `"12"` and `12.0`.
class ArgInteger extends ArgType {
  const ArgInteger({super.example});
}

/// A number; also accepts a numeric string.
class ArgNumber extends ArgType {
  const ArgNumber({super.example});
}

/// A boolean; also accepts `"true"` / `"false"` in any case.
///
/// `1`, `0` and `"yes"` are refused: which way they were meant is a guess, and
/// a wrong guess is worse than a refusal that shows the right shape.
class ArgBoolean extends ArgType {
  const ArgBoolean({super.example});
}

/// One of a fixed set of strings, matched case-insensitively.
class ArgEnum extends ArgType {
  const ArgEnum(this.values, {super.example});
  final List<String> values;
}

/// A property whose schema declares no `type` at all: any JSON, passed through
/// untouched.
///
/// `set_state.value`, `mock_platform_channel.result` and its `event` are the
/// ones today (mcp-inspector's strict mode flags them as bare schemas). They
/// take a scalar, a list or a map, so coercing them — to a string, say — would
/// change what the tool sees.
class ArgAny extends ArgType {
  const ArgAny({super.example});
}

/// A list; also accepts a JSON string of one (`"[{...}]"`).
///
/// A lone object is refused rather than wrapped: `{"tool": ...}` for the
/// `steps` of `execute_action_chain` is a common slip, and one step is what
/// the caller probably meant, but guessing has bitten us before.
class ArgArray extends ArgType {
  const ArgArray({this.items, super.example});
  final ArgType? items;
}

/// A map; also accepts a JSON string of one (`"{\"Email\":\"a@b.c\"}"`).
///
/// [properties] holds the item type when the schema describes one, so an
/// array of objects (`steps`) has its elements coerced one level deep.
class ArgObject extends ArgType {
  const ArgObject({
    this.properties = const {},
    this.required = const [],
    super.example,
  });
  final Map<String, ArgType> properties;
  final List<String> required;
}

/// The type of one JSON Schema property.
ArgType argTypeOf(Object? schema) {
  if (schema is! Map) return const ArgAny();
  final description = schema['description'];
  final example = description is String ? _exampleIn(description) : null;
  final values = schema['enum'];
  if (values is List && values.isNotEmpty) {
    return ArgEnum([for (final value in values) '$value'], example: example);
  }
  switch (schema['type']) {
    case 'string':
      return ArgString(example: example);
    case 'integer':
      return ArgInteger(example: example);
    case 'number':
      return ArgNumber(example: example);
    case 'boolean':
      return ArgBoolean(example: example);
    case 'array':
      final items = schema['items'];
      return ArgArray(
        items: items is Map ? argTypeOf(items) : null,
        example: example,
      );
    case 'object':
      final properties = schema['properties'];
      final required = schema['required'];
      return ArgObject(
        properties: properties is Map
            ? {
                for (final entry in properties.entries)
                  '${entry.key}': argTypeOf(entry.value),
              }
            : const {},
        required: required is List
            ? [for (final name in required) '$name']
            : const [],
        example: example,
      );
    default:
      return ArgAny(example: example);
  }
}

/// The argument types of a tool's `inputSchema` (its `toJson`), read once at
/// registration rather than per call.
Map<String, ArgType> argTypesFromSchema(Map<String, dynamic>? schema) {
  final properties = schema?['properties'];
  if (properties is! Map) return const {};
  return {
    for (final entry in properties.entries)
      '${entry.key}': argTypeOf(entry.value),
  };
}

/// [args] with each value brought to its schema type where that is
/// unambiguous, or the first argument that can't be, as a message.
///
/// A null value means the argument is absent: removed for an optional one,
/// reported as missing for a required one. Keys the schema does not name (an
/// alias like `target`, which [normalizeToolParams] resolves later) are left
/// alone.
({Map<String, dynamic> args, String? problem}) coerceArguments(
  String tool,
  Map<String, dynamic> args,
  Map<String, ArgType> schema, {
  List<String> required = const [],
}) {
  final coerced = <String, dynamic>{};
  for (final entry in args.entries) {
    final type = schema[entry.key];
    final value = entry.value;
    if (value == null) {
      if (required.contains(entry.key)) {
        return (args: args, problem: _missing(tool, entry.key, type));
      }
      continue;
    }
    if (type == null) {
      coerced[entry.key] = value;
      continue;
    }
    final (result, problem) = _coerce(tool, entry.key, type, value);
    if (problem != null) return (args: args, problem: problem);
    coerced[entry.key] = result;
  }
  for (final name in required) {
    if (!coerced.containsKey(name)) {
      return (args: args, problem: _missing(tool, name, schema[name]));
    }
  }
  return (args: coerced, problem: null);
}

(Object?, String?) _coerce(
  String tool,
  String name,
  ArgType type,
  Object? value,
) {
  switch (type) {
    case ArgAny():
      return (value, null);
    case ArgString():
      if (value is String) return (value, null);
      if (value is num || value is bool) return (value.toString(), null);
    case ArgInteger():
      if (value is int) return (value, null);
      if (value is double && value == value.roundToDouble()) {
        return (value.toInt(), null);
      }
      if (value is String) {
        final text = value.trim();
        final parsed = int.tryParse(text);
        if (parsed != null) return (parsed, null);
        final number = double.tryParse(text);
        if (number != null && number == number.roundToDouble()) {
          return (number.toInt(), null);
        }
      }
    case ArgNumber():
      if (value is num) return (value.toDouble(), null);
      if (value is String) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null) return (parsed, null);
      }
    case ArgBoolean():
      if (value is bool) return (value, null);
      if (value is String) {
        final text = value.trim().toLowerCase();
        if (text == 'true') return (true, null);
        if (text == 'false') return (false, null);
      }
    case ArgEnum():
      for (final allowed in type.values) {
        if (allowed.toLowerCase() == value.toString().toLowerCase()) {
          return (allowed, null);
        }
      }
    case ArgArray():
      Object? list = value;
      if (value is String) {
        final text = value.trim();
        if (!text.startsWith('[')) break;
        try {
          list = jsonDecode(text);
        } on FormatException {
          break;
        }
      }
      if (list is! List) break;
      final items = type.items;
      if (items is ArgObject) {
        final elements = <Object?>[];
        for (var i = 0; i < list.length; i++) {
          final element = list[i];
          if (element is! Map) {
            return (null, _problem(tool, '$name[$i]', items, element));
          }
          final (args: map, problem: problem) = coerceArguments(
            tool,
            Map<String, dynamic>.from(element),
            items.properties,
            required: items.required,
          );
          if (problem != null) return (null, problem);
          elements.add(map);
        }
        return (elements, null);
      }
      return (list, null);
    case ArgObject():
      Object? map = value;
      if (value is String) {
        final text = value.trim();
        if (!text.startsWith('{')) break;
        try {
          map = jsonDecode(text);
        } on FormatException {
          break;
        }
      }
      if (map is! Map) break;
      final normalized = Map<String, dynamic>.from(map);
      if (type.properties.isEmpty) return (normalized, null);
      final (args: coerced, problem: problem) = coerceArguments(
        tool,
        normalized,
        type.properties,
        required: type.required,
      );
      if (problem != null) return (null, problem);
      return (coerced, null);
  }
  return (null, _problem(tool, name, type, value));
}

String _missing(String tool, String name, ArgType? type) =>
    '$tool needs $name (${_expected(type)}), e.g. '
    '${_example(name, type)}; nothing was done.';

String _problem(String tool, String name, ArgType type, Object? value) =>
    '$tool: "$name" must be ${_expected(type)}, got '
    '${_describe(value, type)}; nothing was done. Example: '
    '${_example(name, type)}';

String _expected(ArgType? type) => switch (type) {
  ArgAny() => 'any JSON',
  ArgInteger() => 'an integer',
  ArgNumber() => 'a number',
  ArgBoolean() => 'true or false',
  ArgArray(:final items) =>
    items == null ? 'an array' : 'an array of ${_itemNoun(items)}',
  ArgObject() => 'an object',
  ArgEnum(:final values) => 'one of ${values.map((v) => '"$v"').join(', ')}',
  _ => 'a string',
};

String _itemNoun(ArgType item) => switch (item) {
  ArgAny() => 'values',
  ArgObject() => 'objects',
  ArgString() => 'strings',
  ArgInteger() => 'integers',
  ArgNumber() => 'numbers',
  ArgBoolean() => 'booleans',
  ArgArray() => 'arrays',
  ArgEnum() => 'values',
};

/// What the caller actually sent, for the refusal.
String _describe(Object? value, ArgType? type) {
  if (value is String) {
    if (type is ArgArray || type is ArgObject) {
      return 'a string that is not JSON';
    }
    final shown = value.length > 40 ? '${value.substring(0, 37)}...' : value;
    return 'a string "$shown"';
  }
  if (value is List) return 'an array';
  if (value is Map) return 'an object';
  if (value is bool || value is num) return '$value';
  return '${value.runtimeType}';
}

String _example(String name, ArgType? type) =>
    type?.example ?? '"$name": ${_defaultValue(type)}';

String _defaultValue(ArgType? type) => switch (type) {
  ArgAny() => '{}',
  ArgInteger() => '20',
  ArgNumber() => '1.5',
  ArgBoolean() => 'true',
  ArgArray() => '[]',
  ArgObject() => '{}',
  ArgEnum(:final values) => values.isEmpty ? '"text"' : '"${values.first}"',
  _ => '"text"',
};

/// The example a property's description already gives: the inside of
/// `(e.g. ...)` when present, else the rest of the sentence after `e.g.`.
String? _exampleIn(String description) {
  final parenthesized = RegExp(r'\(e\.g\.\s*([^)]*)\)').firstMatch(description);
  if (parenthesized != null) {
    final text = parenthesized.group(1)!.trim();
    if (text.isNotEmpty) return text;
  }
  final rest = RegExp(r'e\.g\.\s*(.+)', dotAll: true).firstMatch(description);
  if (rest == null) return null;
  // The example runs to the end of its sentence; a `{...}` or `[...]` may hold
  // a full stop (`"a@b.dev"`), so cut at the first `. ` that starts a new one.
  final sentence = RegExp(r'\.\s+(?=[A-Z])').firstMatch(rest.group(1)!)?.start;
  var text =
      (sentence == null
              ? rest.group(1)!
              : rest.group(1)!.substring(0, sentence))
          .trim();
  while (text.isNotEmpty && ").;,' ".contains(text[text.length - 1])) {
    text = text.substring(0, text.length - 1).trimRight();
  }
  return text.isEmpty ? null : text;
}
