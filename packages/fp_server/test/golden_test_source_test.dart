import 'dart:io';

import 'package:fp_server/src/golden_test_source.dart';
import 'package:test/test.dart';

void main() {
  test('pumps the real screen, in a ProviderScope for Riverpod', () {
    final src = goldenTestSource(
      name: 'feed_screen',
      import: 'package:hn/ui/feed_screen.dart',
      widget: 'FeedScreen()',
      viewports: {'phone': (390, 844)},
      riverpod: true,
    );
    expect(src, contains("import 'package:hn/ui/feed_screen.dart';"));
    expect(src, contains('ProviderScope(child: MaterialApp('));
    expect(src, contains('home: FeedScreen())'));
    expect(src, contains('const Size(390, 844)'));
    expect(src, contains("'goldens/feed_screen_phone.png'"));
  });

  test('finds the file that declares a class', () {
    final dir = Directory.systemTemp.createTempSync('fp_golden_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/ui/a.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '// class FeedScreen in a comment\nclass FeedScreenX {}',
      );
    File(
      '${dir.path}/ui/b.dart',
    ).writeAsStringSync('final class FeedScreen extends StatelessWidget {}');
    expect(findClassFile(dir, 'FeedScreen')!.path, endsWith('b.dart'));
    expect(findClassFile(dir, 'Nope'), isNull);
  });
}
