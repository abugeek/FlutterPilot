import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

/// The platform side: remembers what reached it, answers like a host with
/// no plugin (null), and keeps the handlers the app sets.
class _Platform extends BinaryMessenger {
  final sent = <String>[];
  ByteData? reply;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    sent.add(channel);
    return Future.value(reply);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Platform platform;
  late BinaryMessenger messenger;

  setUp(() {
    PlatformChannelMocks.debugReset();
    platform = _Platform();
    messenger = PlatformChannelMocks.wrap(platform);
  });

  test(
    'a mocked method answers; the others still reach the platform',
    () async {
      const channel = MethodChannel('app/battery');
      final battery = MethodChannel(
        channel.name,
        const StandardMethodCodec(),
        messenger,
      );
      PlatformChannelMocks.mock('app/battery', method: 'level', result: 42);

      expect(await battery.invokeMethod<int>('level'), 42);
      expect(platform.sent, isEmpty);

      await expectLater(
        battery.invokeMethod<void>('charging'),
        throwsA(isA<MissingPluginException>()),
      );
      expect(platform.sent, ['app/battery']);

      expect(PlatformChannelMocks.calls, [
        {
          'channel': 'app/battery',
          'method': 'level',
          'arguments': '',
          'outcome': 'mocked',
          'times': 1,
        },
        {
          'channel': 'app/battery',
          'method': 'charging',
          'arguments': '',
          'outcome': 'no plugin',
          'times': 1,
        },
      ]);
    },
  );

  test('an error mock throws a PlatformException', () async {
    final location = MethodChannel(
      'app/location',
      const StandardMethodCodec(),
      messenger,
    );
    PlatformChannelMocks.mock(
      'app/location',
      method: 'current',
      errorCode: 'PERMISSION_DENIED',
      errorMessage: 'no',
    );
    await expectLater(
      location.invokeMethod<Object>('current', {'accuracy': 'high'}),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'PERMISSION_DENIED')
            .having((e) => e.message, 'message', 'no'),
      ),
    );
    expect(
      PlatformChannelMocks.calls.single['arguments'],
      '{"accuracy":"high"}',
    );
  });

  test('JSON-codec channels and maps, lists and bytes in results', () async {
    final json = MethodChannel('app/json', const JSONMethodCodec(), messenger);
    PlatformChannelMocks.mock(
      'app/json',
      method: 'get',
      result: {
        'tags': ['a', 'b'],
      },
    );
    expect(await json.invokeMethod<Object>('get'), {
      'tags': ['a', 'b'],
    });

    final std = MethodChannel(
      'app/camera',
      const StandardMethodCodec(),
      messenger,
    );
    PlatformChannelMocks.mock(
      'app/camera',
      method: 'take',
      result: {
        'bytes': {r'$bytes': 'AQID'},
      },
    );
    final photo = await std.invokeMapMethod<String, Object?>('take');
    expect(photo!['bytes'], Uint8List.fromList([1, 2, 3]));
  });

  test('a Pigeon channel gets [result], or [code, message, details]', () async {
    const name = 'dev.flutter.pigeon.pkg.Api.pick';
    final pigeon = BasicMessageChannel<Object?>(
      name,
      const StandardMessageCodec(),
      binaryMessenger: messenger,
    );
    PlatformChannelMocks.mock(name, result: 'file.png');
    expect(await pigeon.send(['gallery']), ['file.png']);
    expect(PlatformChannelMocks.calls.single['arguments'], '["gallery"]');

    PlatformChannelMocks.mock(name, errorCode: 'cancelled');
    expect(await pigeon.send(['gallery']), ['cancelled', null, null]);
  });

  test('credentials in arguments are masked in the call list', () async {
    final auth = MethodChannel(
      'app/auth',
      const StandardMethodCodec(),
      messenger,
    );
    PlatformChannelMocks.mock('app/auth', method: 'signIn', result: true);
    await auth.invokeMethod<bool>('signIn', {'password': 'hunter2'});
    expect(
      PlatformChannelMocks.calls.single['arguments'],
      isNot(contains('hunter2')),
    );
  });

  test('clear removes one method, one channel, or everything', () {
    PlatformChannelMocks.mock('a', method: 'x', result: 1);
    PlatformChannelMocks.mock('a', method: 'y', result: 1);
    PlatformChannelMocks.mock('b', method: 'x', result: 1);
    expect(PlatformChannelMocks.clear(channel: 'a', method: 'x'), 1);
    expect(PlatformChannelMocks.clear(channel: 'a'), 1);
    expect(PlatformChannelMocks.mocks.single['channel'], 'b');
    expect(PlatformChannelMocks.clear(), 1);
  });

  test('an event reaches the EventChannel listener', () async {
    const name = 'app/scanner/events';
    PlatformChannelMocks.mock(name, method: 'listen');
    PlatformChannelMocks.mock(name, method: 'cancel');
    expect(PlatformChannelMocks.emit(name, 'early'), isFalse);

    final events = <Object?>[];
    final errors = <Object>[];
    final sub = EventChannel(
      name,
      const StandardMethodCodec(),
      messenger,
    ).receiveBroadcastStream().listen(events.add, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    expect(PlatformChannelMocks.listeners, [name]);

    expect(PlatformChannelMocks.emit(name, {'code': '4006381333931'}), isTrue);
    PlatformChannelMocks.emit(name, null, errorCode: 'CAMERA_ERROR');
    await Future<void>.delayed(Duration.zero);

    // The event sent before anyone listened waited for the listener.
    expect(events, [
      'early',
      {'code': '4006381333931'},
    ]);
    expect((errors.single as PlatformException).code, 'CAMERA_ERROR');
    await sub.cancel();
    expect(PlatformChannelMocks.listeners, isEmpty);
  });
}
