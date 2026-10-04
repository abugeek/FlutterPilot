import 'package:flutterpilot_server/src/param_aliases.dart';
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
}
