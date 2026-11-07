import 'package:fp_server/src/source_span.dart';
import 'package:test/test.dart';

void main() {
  String call(String src, int line, int col) {
    final span = constructorSpanAt(src, line, col)!;
    return src.substring(span.offset, span.end);
  }

  test('matches parentheses past strings, comments and interpolation', () {
    const src = '''
Widget build() {
  return Padding(
    padding: const EdgeInsets.all(8), // not ) here
    child: Text(
      'a ) b \${f(")")} c',
      style: TextStyle(color: x), /* ) */
    ),
  );
}
''';
    final padding = constructorSpanAt(src, 2, 10)!;
    expect(src.substring(padding.offset, padding.end), startsWith('Padding('));
    expect(src.substring(padding.offset, padding.end), endsWith('),\n  )'));
    // Only the call's own arguments, not TextStyle's color.
    expect(padding.namedArgs, ['padding', 'child']);

    expect(call(src, 4, 12), contains("'a ) b"));
    expect(constructorSpanAt(src, 4, 12)!.namedArgs, ['style']);
  });

  test('triple-quoted and raw strings, named constructors, generics', () {
    const src = "final w = ListView.builder(a: '''x ) y''', b: r'\\)', c: f<int>(1));";
    final span = constructorSpanAt(src, 1, 11)!;
    expect(src.substring(span.offset, span.end), endsWith("f<int>(1))"));
    expect(span.namedArgs, ['a', 'b', 'c']);
  });

  test('null when no call starts there or it never closes', () {
    expect(constructorSpanAt('  x + 1', 1, 3), isNull);
    expect(constructorSpanAt('Foo(a: 1', 1, 1), isNull);
    expect(constructorSpanAt('Foo()', 9, 1), isNull);
  });

  test('rewinds when column is inside identifier or line starts with spaces', () {
    const src = '  runApp(const MyApp());';
    // Column 5 is 'n' in runApp: rewinds to start of runApp
    final spanMid = constructorSpanAt(src, 1, 5)!;
    expect(src.substring(spanMid.offset, spanMid.end), 'runApp(const MyApp())');

    // Column 1 is leading space: advances to runApp
    final spanLead = constructorSpanAt(src, 1, 1)!;
    expect(src.substring(spanLead.offset, spanLead.end), 'runApp(const MyApp())');
  });

  test('named constructor when column points to constructor name', () {
    const src = '  floatingActionButton: FloatingActionButton.extended(\n'
        '    key: const Key("add_todo"),\n'
        '    label: const Text("Add"),\n'
        '  );';
    // Column 46 is 'e' of extended
    final spanNamed = constructorSpanAt(src, 1, 46);
    expect(spanNamed, isNotNull);
    expect(src.substring(spanNamed!.offset, spanNamed.end), startsWith('FloatingActionButton.extended('));

    // Column 1 advances past 'floatingActionButton: '
    final spanCol1 = constructorSpanAt(src, 1, 1);
    expect(spanCol1, isNotNull);
    expect(src.substring(spanCol1!.offset, spanCol1.end), startsWith('FloatingActionButton.extended('));
  });

  test('type arguments and library prefixes with named constructors', () {
    const src = '  final x = material.List<String>.filled(5, "a");';
    // Inside filled
    final spanFilled = constructorSpanAt(src, 1, 37);
    expect(spanFilled, isNotNull);
    expect(src.substring(spanFilled!.offset, spanFilled.end), 'material.List<String>.filled(5, "a")');
  });

  test('locating parent span enclosing a child widget', () {
    const src = '''
Widget build() {
  return Center(
    child: FloatingActionButton.extended(
      key: const Key("add_todo"),
      label: const Text("Add"),
    ),
  );
}
''';
    final childSpan = constructorSpanAt(src, 3, 12)!;
    expect(src.substring(childSpan.offset, childSpan.end), startsWith('FloatingActionButton.extended('));

    final parentSpan = constructorSpanAt(src, 2, 10)!;
    expect(src.substring(parentSpan.offset, parentSpan.end), startsWith('Center('));
    expect(parentSpan.offset < childSpan.offset, isTrue);
    expect(parentSpan.end > childSpan.end, isTrue);

    final foundParent = enclosingConstructorSpan(src, childSpan.offset, childSpan.end, hintLine: 3);
    expect(foundParent, isNotNull);
    expect(foundParent!.offset, parentSpan.offset);
    expect(foundParent.end, parentSpan.end);
  });

  test('innermost enclosing constructor on same line with outer wrapper', () {
    const src = '''
Widget build() {
  return Scaffold(
    appBar: AppBar(title: Center(
      child: const Text('Hacker News'),
    )),
  );
}
''';
    final textSpan = constructorSpanAt(src, 4, 14)!;
    expect(src.substring(textSpan.offset, textSpan.end), "const Text('Hacker News')");

    final innermost = enclosingConstructorSpan(src, textSpan.offset, textSpan.end, hintLine: 4);
    expect(innermost, isNotNull);
    expect(src.substring(innermost!.offset, innermost.end), startsWith('Center('));
  });
}
