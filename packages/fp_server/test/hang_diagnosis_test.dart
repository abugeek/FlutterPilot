import 'package:fp_server/src/hang_diagnosis.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

Frame frame(String function, String uri, int line, {String? type}) => Frame(
  index: 0,
  function: FuncRef(
    id: 'f',
    name: function,
    owner: type == null ? null : ClassRef(id: 'c', name: type),
    isStatic: false,
    isConst: false,
    implicit: false,
    isAbstract: false,
    isGetter: false,
    isSetter: false,
  ),
  location: SourceLocation(
    script: ScriptRef(id: 's', uri: uri),
    tokenPos: 0,
    line: line,
  ),
);

void main() {
  test('only the no-answer errors are diagnosed', () {
    expect(
      isNoAnswer('[timeout] No answer from the app within 30 s. The action…'),
      isTrue,
    );
    expect(isNoAnswer('[timeout] Extension call timed out.'), isTrue);
    expect(isNoAnswer('[extensionError] Widget not found'), isFalse);
  });

  test('a frame is its function and where it is', () {
    expect(
      describeFrame(
        frame('recompute', 'package:shop/cart.dart', 88, type: 'CartNotifier'),
      ),
      'CartNotifier.recompute (package:shop/cart.dart:88)',
    );
  });

  test('app code below the shown frames is still pointed out', () {
    final stack = describeStack(
      [
        for (var i = 0; i < 10; i++)
          frame('f$i', 'package:flutter/src/widgets/framework.dart', i),
        frame('build', 'package:shop/home.dart', 42, type: 'HomeScreen'),
      ],
      max: 3,
      appUriPrefixes: ['package:shop/'],
    );
    expect(stack.split('\n'), hasLength(5));
    expect(stack, contains('f2 (package:flutter/'));
    expect(
      stack,
      endsWith('HomeScreen.build (package:shop/home.dart:42)  <- app code'),
    );
  });
}
