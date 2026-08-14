import 'package:flutterpilot_server/src/device_runtime_context.dart';
import 'package:test/test.dart';

void main() {
  test('keeps scheduler and isolate state independent per device', () async {
    final first = DeviceRuntimeContext(
      deviceId: 'ios',
      uri: 'ws://127.0.0.1:1/ios/ws',
    );
    final second = DeviceRuntimeContext(
      deviceId: 'android',
      uri: 'ws://127.0.0.1:2/android/ws',
    );

    first.cachedMainIsolateId = 'isolate-ios';
    second.cachedMainIsolateId = 'isolate-android';
    expect(first.cachedMainIsolateId, isNot(second.cachedMainIsolateId));
    expect(first.scheduler, isNot(same(second.scheduler)));

    await first.dispose();
    expect(first.cachedMainIsolateId, isNull);
    expect(second.cachedMainIsolateId, 'isolate-android');

    await second.dispose();
  });
}
