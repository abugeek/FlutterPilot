import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/restart_store.dart';

void main() {
  test('data left before a restart is read once, then gone', () {
    RestartStore.save({
      'httpMocks': [
        {'urlPattern': '/ping', 'statusCode': 500},
      ],
    });
    RestartStore.debugReset(); // what a hot restart does to the cache
    expect(RestartStore.take('httpMocks'), [
      {'urlPattern': '/ping', 'statusCode': 500},
    ]);
    expect(RestartStore.take('httpMocks'), isNull);
    // The file is gone: a later restart starts clean.
    RestartStore.debugReset();
    expect(RestartStore.take('httpMocks'), isNull);
  });
}
