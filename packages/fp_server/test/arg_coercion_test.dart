import 'package:fp_server/src/arg_coercion.dart';
import 'package:test/test.dart';

void main() {
  ({Map<String, dynamic> args, String? problem}) coerce(
    Map<String, ArgType> schema,
    Map<String, dynamic> args, {
    List<String> required = const [],
  }) => coerceArguments('tool', args, schema, required: required);

  group('integer', () {
    const schema = {'limit': ArgInteger()};

    test('accepts an int, and the string and double forms of one', () {
      expect(coerce(schema, {'limit': 12}).args['limit'], 12);
      expect(coerce(schema, {'limit': '12'}).args['limit'], 12);
      expect(coerce(schema, {'limit': 12.0}).args['limit'], 12);
      expect(coerce(schema, {'limit': ' 12 '}).args['limit'], 12);
    });

    test('refuses "12.5", 12.5, "abc" and a bool', () {
      for (final value in <Object?>[
        '12.5',
        12.5,
        'abc',
        true,
        [1],
        {},
      ]) {
        final problem = coerce(schema, {'limit': value}).problem;
        expect(problem, isNotNull, reason: '$value');
        expect(problem, contains('an integer'), reason: '$value');
        expect(problem, contains('nothing was done'), reason: '$value');
      }
    });
  });

  group('number', () {
    const schema = {'ratio': ArgNumber()};

    test('accepts numbers and numeric strings', () {
      expect(coerce(schema, {'ratio': 1.5}).args['ratio'], 1.5);
      expect(coerce(schema, {'ratio': 3}).args['ratio'], 3.0);
      expect(coerce(schema, {'ratio': '1.5'}).args['ratio'], 1.5);
    });

    test('refuses a non-numeric string and a bool', () {
      for (final value in <Object?>[
        'abc',
        true,
        [1],
      ]) {
        expect(
          coerce(schema, {'ratio': value}).problem,
          isNotNull,
          reason: '$value',
        );
      }
    });
  });

  group('boolean', () {
    const schema = {'enabled': ArgBoolean()};

    test('accepts a bool and "true"/"false" in any case', () {
      expect(coerce(schema, {'enabled': true}).args['enabled'], true);
      expect(coerce(schema, {'enabled': 'TRUE'}).args['enabled'], true);
      expect(coerce(schema, {'enabled': 'False'}).args['enabled'], false);
    });

    // 1/0 and "yes"/"no" are a guess; a refusal that shows the shape is better
    // than a wrong guess.
    test('refuses 1, 0 and "yes"', () {
      for (final value in <Object?>[1, 0, 'yes', 'no', '1']) {
        final problem = coerce(schema, {'enabled': value}).problem;
        expect(problem, isNotNull, reason: '$value');
        expect(problem, contains('true or false'), reason: '$value');
      }
    });
  });

  group('string', () {
    const schema = {'key': ArgString()};

    test('accepts a string, and stringifies a number or bool', () {
      expect(coerce(schema, {'key': 'Save'}).args['key'], 'Save');
      expect(coerce(schema, {'key': 3}).args['key'], '3');
      expect(coerce(schema, {'key': true}).args['key'], 'true');
    });

    test('refuses an array or an object', () {
      expect(
        coerce(schema, {
          'key': [1],
        }).problem,
        isNotNull,
      );
      expect(
        coerce(schema, {
          'key': {'a': 1},
        }).problem,
        isNotNull,
      );
    });
  });

  group('array', () {
    const schema = {'items': ArgArray()};

    test('accepts a list and a JSON string of one', () {
      expect(
        coerce(schema, {
          'items': [1, 2],
        }).args['items'],
        [1, 2],
      );
      expect(coerce(schema, {'items': '[1, 2]'}).args['items'], [1, 2]);
      expect(coerce(schema, {'items': ' [] '}).args['items'], isEmpty);
    });

    test('refuses a string that is not JSON and a lone object', () {
      for (final value in <Object?>['nope', '{"a": 1}']) {
        final problem = coerce(schema, {'items': value}).problem;
        expect(problem, isNotNull, reason: '$value');
        expect(
          problem,
          contains('a string that is not JSON'),
          reason: '$value',
        );
      }
      final loneObject = coerce(schema, {
        'items': {'a': 1},
      }).problem;
      expect(loneObject, isNotNull);
      expect(loneObject, contains('an object'));
    });

    test('coerces an object element one level deep (steps[].arguments)', () {
      const steps = {
        'steps': ArgArray(
          items: ArgObject(
            properties: {
              'tool': ArgString(),
              'arguments': ArgObject(properties: {'durationMs': ArgInteger()}),
            },
            required: ['tool'],
          ),
        ),
      };
      final result = coerce(steps, {
        'steps': '[{"tool": "tap_widget", "arguments": {"durationMs": "10"}}]',
      });
      expect(result.problem, isNull);
      final list = result.args['steps'] as List;
      final step = list.single as Map;
      expect(step['tool'], 'tap_widget');
      expect((step['arguments'] as Map)['durationMs'], 10);
    });

    test('names a bad element by index', () {
      const steps = {
        'steps': ArgArray(
          items: ArgObject(
            properties: {'tool': ArgString()},
            required: ['tool'],
          ),
        ),
      };
      final problem = coerce(steps, {
        'steps': [
          {'tool': 'tap_widget'},
          {'arguments': {}},
        ],
      }).problem;
      expect(problem, isNotNull);
      expect(problem, contains('tool'));
    });

    test('names a nested property by its whole path', () {
      const steps = {
        'steps': ArgArray(
          items: ArgObject(
            properties: {
              'tool': ArgString(),
              'arguments': ArgObject(properties: {'durationMs': ArgInteger()}),
            },
            required: ['tool'],
          ),
        ),
      };
      // `arguments` itself is not an object.
      final notObject = coerce(steps, {
        'steps': [
          {'tool': 'tap_widget', 'arguments': 5},
        ],
      }).problem;
      expect(notObject, contains('steps[0].arguments'));
      // A property inside `arguments` names the whole path too.
      final badProperty = coerce(steps, {
        'steps': [
          {
            'tool': 'tap_widget',
            'arguments': {'durationMs': 'abc'},
          },
        ],
      }).problem;
      expect(badProperty, contains('steps[0].arguments.durationMs'));
      // A missing required nested field is named the same way.
      final missing = coerce(steps, {
        'steps': [
          {'arguments': <String, dynamic>{}},
        ],
      }).problem;
      expect(missing, contains('steps[0].tool'));
    });
  });

  group('object', () {
    const schema = {'fields': ArgObject()};

    test('accepts a map and a JSON string of one', () {
      expect(
        coerce(schema, {
          'fields': {'Email': 'a@b.c'},
        }).args['fields'],
        {'Email': 'a@b.c'},
      );
      expect(coerce(schema, {'fields': '{"Email": "a@b.c"}'}).args['fields'], {
        'Email': 'a@b.c',
      });
    });

    test('refuses a string that is not JSON and a list', () {
      for (final value in <Object?>[
        'nope',
        '[1]',
        [1],
      ]) {
        expect(
          coerce(schema, {'fields': value}).problem,
          isNotNull,
          reason: '$value',
        );
      }
    });
  });

  group('any (no type in the schema)', () {
    const schema = {'value': ArgAny()};

    test('passes a scalar, a list or a JSON string through untouched', () {
      expect(coerce(schema, {'value': 42}).args['value'], 42);
      expect(
        coerce(schema, {
          'value': [1, 2],
        }).args['value'],
        [1, 2],
      );
      expect(coerce(schema, {'value': '{"a": 1}'}).args['value'], '{"a": 1}');
    });
  });

  group('enum', () {
    const schema = {
      'mode': ArgEnum(['dark', 'light']),
    };

    test('matches case-insensitively to the canonical value', () {
      expect(coerce(schema, {'mode': 'DARK'}).args['mode'], 'dark');
      expect(coerce(schema, {'mode': 'light'}).args['mode'], 'light');
    });

    test('refuses a value outside the set, and lists the allowed ones', () {
      final problem = coerce(schema, {'mode': 'blue'}).problem;
      expect(problem, isNotNull);
      expect(problem, contains('"dark"'));
      expect(problem, contains('"light"'));
    });
  });

  group('null and required', () {
    test('a null optional argument is removed', () {
      final result = coerce({'limit': ArgInteger()}, {'limit': null});
      expect(result.problem, isNull);
      expect(result.args, isEmpty);
    });

    test('a null required argument is reported as missing', () {
      final result = coerce(
        {'limit': ArgInteger()},
        {'limit': null},
        required: ['limit'],
      );
      expect(result.problem, contains('needs limit'));
    });

    test('a missing required argument is reported with its type and name', () {
      final result = coerce(
        {'steps': ArgArray(items: ArgObject())},
        const {},
        required: ['steps'],
      );
      expect(result.problem, isNotNull);
      expect(result.problem, contains('tool needs steps'));
      expect(result.problem, contains('an array of objects'));
      expect(result.problem, contains('nothing was done'));
    });
  });

  group('messages', () {
    test('use the description example when it has one', () {
      final types = argTypesFromSchema({
        'properties': {
          'route': {'type': 'string', 'description': 'Route (e.g. "/home").'},
        },
        'required': ['route'],
      });
      final problem = coerce(types, const {}, required: ['route']).problem;
      expect(problem, contains('e.g. "/home"'));
    });

    test('generate an example from the type otherwise', () {
      final types = argTypesFromSchema({
        'properties': {
          'limit': {'type': 'integer', 'description': 'How many.'},
        },
      });
      final problem = coerce(types, {'limit': 'abc'}).problem;
      expect(problem, contains('Example: "limit": 20'));
    });
  });

  group('argTypesFromSchema', () {
    test('reads type, enum, item and required from the JSON schema', () {
      final types = argTypesFromSchema({
        'properties': {
          'route': {'type': 'string', 'description': 'Route (e.g. "/home").'},
          'mode': {
            'type': 'string',
            'enum': ['dark', 'light'],
          },
          'limit': {'type': 'integer'},
          'steps': {
            'type': 'array',
            'items': {'type': 'object'},
            'description': 'Steps, e.g. [{"tool": "tap"}]. Tools: tap.',
          },
          'value': {'description': 'Any JSON.'},
        },
        'required': ['steps'],
      });
      expect(types['route'], isA<ArgString>());
      expect(types['route']!.example, '"/home"');
      expect((types['mode'] as ArgEnum).values, ['dark', 'light']);
      expect(types['limit'], isA<ArgInteger>());
      expect(types['steps'], isA<ArgArray>());
      expect((types['steps'] as ArgArray).items, isA<ArgObject>());
      expect(types['steps']!.example, '[{"tool": "tap"}]');
      expect(types['value'], isA<ArgAny>());
    });

    test('is empty without properties', () {
      expect(argTypesFromSchema(null), isEmpty);
      expect(argTypesFromSchema(const {}), isEmpty);
    });
  });
}
