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
}
