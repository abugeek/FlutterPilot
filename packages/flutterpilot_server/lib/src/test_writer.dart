/// Turns the steps the SDK recorded (ROADMAP §6) into an `integration_test`
/// that starts the app from its real entrypoint and replays them with
/// `flutter_test` finders.
class GeneratedTest {
  GeneratedTest(this.source, {required this.skipped, required this.unstable});

  final String source;

  /// Recorded steps a test can't replay (navigate_to, set_slider_value…).
  final List<String> skipped;

  /// Steps found by position: they break when the screen's content changes.
  final List<String> unstable;
}

/// [mainImport] is the entrypoint's package URI (`package:app/main.dart`).
GeneratedTest writeIntegrationTest({
  required String name,
  required String mainImport,
  required List<Map<String, dynamic>> steps,
}) {
  final body = StringBuffer();
  final skipped = <String>[];
  final unstable = <String>[];
  var usesDio = false;
  var usesGestures = false;
  var usesSemantics = false;
  var usesServices = false;
  var secrets = 0;

  void line(String s) => body.writeln('    $s');

  var n = 0;
  for (final step in steps) {
    final type = step['type'] as String?;
    final f = step['finder'] as String?;
    if (f != null && step['stable'] == false) unstable.add(f);
    n++;
    switch (type) {
      case 'tap' || 'doubleTap' || 'longPress' || 'secondaryTap' when f != null:
        line('// $n. $type ${_label(step)}');
        line('await _show(tester, $f);');
        switch (type) {
          case 'doubleTap':
            usesGestures = true;
            line('await tester.tap($f);');
            line('await tester.pump(kDoubleTapMinTime);');
            line('await tester.tap($f);');
          case 'longPress':
            line('await tester.longPress($f);');
          case 'secondaryTap':
            usesGestures = true;
            line('await tester.tap($f, buttons: kSecondaryButton);');
          default:
            line('await tester.tap($f);');
        }
        line('await _settle(tester);');
      case 'tapAt':
        final x = (step['x'] as num).round();
        final y = (step['y'] as num).round();
        line('// $n. tap at a point: nothing tappable was found there');
        line('await tester.tapAt(const Offset($x, $y));');
        line('await _settle(tester);');
        unstable.add('tap at ($x, $y)');
      case 'enterText' when f != null:
        final secret = step['secret'] as int?;
        final String value;
        if (secret != null) {
          secrets = secret > secrets ? secret : secrets;
          value = "const String.fromEnvironment('FP_SECRET_$secret')";
        } else {
          value = dartString(step['text'] as String? ?? '');
        }
        line('// $n. enter text${secret != null ? ' (obscured field)' : ''}');
        line('await _show(tester, $f);');
        line('await tester.enterText($f, $value);');
        line('await _settle(tester);');
      case 'pressKey':
        final key = step['key'] as String? ?? '';
        final code = _keyCode(
          key,
          (step['modifiers'] as List?)?.cast<String>() ?? const [],
          inField: step['inField'] == true,
        );
        if (code == null) {
          line('// $n. Not replayed: press_key "$key"');
          skipped.add('press_key "$key"');
        } else {
          usesServices = true;
          line('// $n. press_key "$key"');
          for (final c in code) {
            line(c);
          }
          line('await _settle(tester);');
        }
      case 'scrollTo' when f != null:
        final scrollable = step['scrollable'] as String?;
        line('// $n. scroll until visible');
        line(
          'await tester.scrollUntilVisible($f, 200'
          '${scrollable == null ? '' : ', scrollable: $scrollable'});',
        );
        line('await _settle(tester);');
      case 'drag' when f != null:
        final dx = (step['dx'] as num).round();
        final dy = (step['dy'] as num).round();
        line('// $n. drag');
        line('await _show(tester, $f);');
        line('await tester.drag($f, const Offset($dx, $dy));');
        line('await _settle(tester);');
      case 'back':
        line('// $n. system back');
        line(
          '// ignore: invalid_use_of_protected_member, '
          'invalid_use_of_visible_for_testing_member',
        );
        line('await tester.binding.handlePopRoute();');
        line('await _settle(tester);');
      case 'expectVisible' || 'waitFor' when f != null:
        line(
          '// $n. ${type == 'waitFor' ? 'wait for' : 'expect'} '
          '${_label(step)}',
        );
        line('await _show(tester, $f);');
      case 'expectText':
        final text = dartString(step['text'] as String? ?? '');
        final finder = step['exact'] == true
            ? 'find.text($text)'
            : 'find.textContaining($text, findRichText: true)';
        line('// $n. expect text');
        line('await _show(tester, $finder);');
      case 'expectCount':
        final widgetType = step['widgetType'] as String? ?? '';
        final count = step['count'] as int? ?? 0;
        final finder =
            RegExp(r'^[A-Z]\w*$').hasMatch(widgetType) &&
                frameworkTypes.contains(widgetType)
            ? 'find.byType($widgetType)'
            : 'find.byWidgetPredicate((w) => w.runtimeType.toString() == '
                  '${dartString(widgetType)})';
        line('// $n. expect $count × $widgetType');
        line('expect($finder, findsNWidgets($count));');
      case 'expectEnabled' when f != null:
        usesSemantics = true;
        final enabled = step['enabled'] != false;
        line('// $n. expect ${enabled ? 'enabled' : 'disabled'}');
        line('await _show(tester, $f);');
        line(
          'expect(tester.getSemantics($f), '
          'containsSemantics(isEnabled: $enabled));',
        );
      case 'mock':
        usesDio = true;
        final delay = step['delayMs'] as int? ?? 0;
        line('// $n. mocked response');
        line(
          'DioPilotInterceptor.mock(${dartString('${step['urlPattern']}')}, '
          'statusCode: ${step['statusCode']}, '
          'body: ${dartString('${step['body'] ?? ''}')}'
          '${delay > 0 ? ', delayMs: $delay' : ''});',
        );
      case 'clearMocks':
        usesDio = true;
        final pattern = step['urlPattern'] as String?;
        line('// $n. mocks cleared');
        line(
          'DioPilotInterceptor.clearMocks('
          '${pattern == null ? '' : dartString(pattern)});',
        );
      case 'skipped':
        line('// $n. Not replayed: ${step['what']}');
        skipped.add('${step['what']}');
      default:
        line('// $n. Not replayed: $type');
        skipped.add('$type');
    }
  }

  final defines = [
    for (var i = 1; i <= secrets; i++) '--dart-define=FP_SECRET_$i=…',
  ].join(' ');
  final out = StringBuffer()
    ..writeln('// Generated by FlutterPilot (generate_test) from what an agent')
    ..writeln('// did in the running app. Run it with:')
    ..writeln(
      '//   flutter test integration_test/${name}_test.dart'
      '${defines.isEmpty ? '' : ' $defines'}',
    )
    ..writeln("import 'package:flutter/material.dart';");
  if (usesGestures) out.writeln("import 'package:flutter/gestures.dart';");
  if (usesServices) out.writeln("import 'package:flutter/services.dart';");
  out
    ..writeln("import 'package:flutter_test/flutter_test.dart';")
    ..writeln("import 'package:integration_test/integration_test.dart';");
  if (usesDio) {
    out.writeln("import 'package:flutterpilot_dio/flutterpilot_dio.dart';");
  }
  out
    ..writeln("import '$mainImport' as app;")
    ..writeln()
    ..writeln('void main() {')
    ..writeln('  IntegrationTestWidgetsFlutterBinding.ensureInitialized();')
    ..writeln()
    ..writeln('  testWidgets(${dartString(name)}, (tester) async {');
  if (usesSemantics) {
    out.writeln('    final semantics = tester.ensureSemantics();');
  }
  out
    ..writeln('    app.main();')
    ..writeln('    await _settle(tester);')
    ..writeln()
    ..write(body);
  if (usesSemantics) out.writeln('    semantics.dispose();');
  out
    ..writeln('  });')
    ..writeln('}')
    ..writeln()
    ..writeln(_helpers);
  return GeneratedTest(out.toString(), skipped: skipped, unstable: unstable);
}

String _label(Map<String, dynamic> step) {
  final target = step['target'];
  return target == null ? '' : '"$target"';
}

/// What failed in a `flutter test` run of [source] (written to a file
/// named [fileName]): the recorded step it stopped at, then the test
/// framework's message.
String describeTestFailure(String output, String source, String fileName) {
  final lines = output.split('\n');
  final start = lines.indexWhere(
    (l) => l.contains('EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK'),
  );
  final message = start < 0
      ? lines.skip(lines.length > 30 ? lines.length - 30 : 0).join('\n')
      : lines
            .skip(start + 1)
            .takeWhile(
              (l) =>
                  !l.startsWith('When the exception') &&
                  !l.startsWith('#') &&
                  !l.startsWith('═'),
            )
            .where((l) => l.trim().isNotEmpty)
            .take(12)
            .join('\n');
  // The frame in main's test body is the step's own line.
  final at = RegExp(
    'main\\.<anonymous closure> \\(.*${RegExp.escape(fileName)}:(\\d+)',
  ).firstMatch(output);
  final line = at == null ? null : int.parse(at.group(1)!);
  String? step;
  if (line != null) {
    final src = source.split('\n');
    for (var i = line - 1; i >= 0 && i < src.length; i--) {
      final m = RegExp(r'^\s*// (\d+)\. (.*)$').firstMatch(src[i]);
      if (m != null) {
        step = '${m.group(1)}, ${m.group(2)}';
        break;
      }
    }
  }
  return [
    if (step != null) 'Failed at step $step (line $line).',
    message,
  ].join('\n');
}

/// `flutter_test` code for a key the agent pressed, or null if there is no
/// good equivalent.
List<String>? _keyCode(
  String key,
  List<String> modifiers, {
  required bool inField,
}) {
  final lower = key.toLowerCase();
  // In a field Enter submits: the keyboard's action button does that in a
  // test, whatever the field's textInputAction.
  if ((lower == 'enter' || lower == 'return') && inField && modifiers.isEmpty) {
    return ['await tester.testTextInput.receiveAction(TextInputAction.done);'];
  }
  final logical = _logicalKey(lower);
  if (logical == null) return null;
  final mods = [
    for (final m in modifiers)
      switch (m.toLowerCase()) {
        'ctrl' || 'control' => 'LogicalKeyboardKey.control',
        'shift' => 'LogicalKeyboardKey.shift',
        'alt' || 'option' => 'LogicalKeyboardKey.alt',
        'meta' || 'cmd' || 'command' => 'LogicalKeyboardKey.meta',
        _ => null,
      },
  ];
  if (mods.contains(null)) return null;
  return [
    for (final m in mods) 'await tester.sendKeyDownEvent($m);',
    'await tester.sendKeyEvent($logical);',
    for (final m in mods.reversed) 'await tester.sendKeyUpEvent($m);',
  ];
}

String? _logicalKey(String lower) {
  const named = {
    'enter': 'enter',
    'return': 'enter',
    'tab': 'tab',
    'escape': 'escape',
    'esc': 'escape',
    'backspace': 'backspace',
    'delete': 'delete',
    'space': 'space',
    'home': 'home',
    'end': 'end',
    'pageup': 'pageUp',
    'pagedown': 'pageDown',
    'arrowup': 'arrowUp',
    'up': 'arrowUp',
    'arrowdown': 'arrowDown',
    'down': 'arrowDown',
    'arrowleft': 'arrowLeft',
    'left': 'arrowLeft',
    'arrowright': 'arrowRight',
    'right': 'arrowRight',
  };
  final name = named[lower];
  if (name != null) return 'LogicalKeyboardKey.$name';
  if (RegExp(r'^[a-z]$').hasMatch(lower)) {
    return 'LogicalKeyboardKey.key${lower.toUpperCase()}';
  }
  if (RegExp(r'^[0-9]$').hasMatch(lower)) {
    return 'LogicalKeyboardKey.digit$lower';
  }
  return null;
}

/// A single-quoted Dart string literal.
String dartString(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}

/// Types `package:flutter/material.dart` exports (as the SDK's finder
/// writer uses them).
const frameworkTypes = {
  'ElevatedButton',
  'TextButton',
  'OutlinedButton',
  'FilledButton',
  'IconButton',
  'FloatingActionButton',
  'BackButton',
  'CloseButton',
  'TextField',
  'TextFormField',
  'Checkbox',
  'CheckboxListTile',
  'Switch',
  'SwitchListTile',
  'Radio',
  'RadioListTile',
  'Slider',
  'ListTile',
  'Card',
  'InkWell',
  'GestureDetector',
  'Chip',
  'ChoiceChip',
  'FilterChip',
  'ActionChip',
  'InputChip',
  'Tab',
  'NavigationDestination',
  'PopupMenuButton',
  'DropdownButton',
  'MenuItemButton',
  'Text',
  'Icon',
  'SegmentedButton',
  'ExpansionTile',
  'SearchBar',
};

const _helpers = '''
/// Pumps until [finder] finds something: the app may still be loading.
Future<void> _show(WidgetTester tester, Finder finder) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

/// Lets the app react: frames until it is idle, 3 s at most (a spinner
/// never is, so no pumpAndSettle).
Future<void> _settle(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  do {
    await tester.pump(const Duration(milliseconds: 50));
  } while (tester.binding.hasScheduledFrame && DateTime.now().isBefore(end));
}''';
