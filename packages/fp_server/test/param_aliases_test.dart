import 'package:fp_server/src/param_aliases.dart';
import 'package:test/test.dart';

void main() {
  // get_network_logs(clear: true) answered with the logs and cleared
  // nothing (field test #280).
  test('an argument the tool does not have is unknown', () {
    expect(unknownToolArguments(['clear', 'limit'], ['limit', 'url']), [
      'clear',
    ]);
    expect(unknownToolArguments(['anything'], []), ['anything']);
    expect(unknownToolArguments([], ['limit']), isEmpty);
  });

  test('an alias of a parameter the tool has is known', () {
    expect(unknownToolArguments(['target', 'selector'], ['key']), isEmpty);
    expect(unknownToolArguments(['dbName'], ['database', 'sql']), isEmpty);
    expect(unknownToolArguments(['provider'], ['name', 'value']), isEmpty);
    // ...but only for a tool that has that parameter.
    expect(unknownToolArguments(['target'], ['route']), ['target']);
  });

  test('a renamed parameter works under both names, its type kept', () {
    expect(
      unknownToolArguments(['clear_first'], ['text', 'clearFirst']),
      isEmpty,
    );
    expect(withFormerNames({'text': 'a', 'clearFirst': false}), {
      'text': 'a',
      'clearFirst': false,
      'clear_first': false,
    });
    expect(withFormerNames({'since_seconds': 5}), {'since_seconds': 5});
  });

  // Task 02: coercion runs before the aliases are copied, so the value an
  // alias receives is the coerced one (a number sent for a text key becomes
  // its string).
  test('a coerced value is what the alias copies', () {
    expect(normalizeToolParams({'target': 3})['key'], '3');
    expect(normalizeToolParams({'target': true})['key'], 'true');
  });
}
