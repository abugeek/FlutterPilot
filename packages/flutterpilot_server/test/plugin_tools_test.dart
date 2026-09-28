import 'dart:io';

import 'package:flutterpilot_server/src/plugin_tools.dart';
import 'package:test/test.dart';

void main() {
  test('every extension a plugin tool waits for is registered by a plugin', () {
    final registered = <String>{
      for (final file
          in Directory('../plugins')
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (f) => f.path.contains('/lib/') && f.path.endsWith('.dart'),
              ))
        ...RegExp(
          r"[rR]egisterExtension\(\s*'(ext\.flutterpilot\.\w+)'",
        ).allMatches(file.readAsStringSync()).map((m) => m.group(1)!),
    };
    expect(registered, isNotEmpty);
    for (final MapEntry(key: tool, value: extensions)
        in pluginToolExtensions.entries) {
      for (final e in extensions) {
        expect(registered, contains(e), reason: '$tool waits for $e');
      }
    }
  });
}
