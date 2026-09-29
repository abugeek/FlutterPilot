import 'dart:io';

import 'package:test/test.dart';

/// Every service extension the SDK registers is one a tool calls. An
/// extension nothing calls is code nobody exercises (stream_inspector,
/// tapAt, jumpToScreen, ... lived on that way after their tools were gone).
void main() {
  Set<String> namesIn(String folder, RegExp pattern) => {
    for (final file in Directory(folder).listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart'))
        for (final match in pattern.allMatches(file.readAsStringSync()))
          match.group(1)!,
  };

  test('the server calls every extension the SDK registers', () {
    final registered = namesIn(
      '../flutterpilot_sdk/lib',
      RegExp(r"registerExtension\(\s*'ext\.flutterpilot\.(\w+)'"),
    );
    final called = namesIn('lib', RegExp(r'ext\.flutterpilot\.(\w+)'));

    expect(registered, isNotEmpty);
    expect(registered.difference(called), isEmpty);
  });
}
