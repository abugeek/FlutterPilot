import 'package:flutterpilot_server/src/android_device.dart';
import 'package:test/test.dart';

void main() {
  test('parseAdbDevices: state, model, wireless', () {
    final d = parseAdbDevices('''
List of devices attached
ALDE6R2516001927       device usb:2-1.2 product:TFY-LX1 model:TFY_LX1 device:HNTFY-Q transport_id:3
192.168.1.5:5555       offline
emulator-5554          unauthorized
''');
    expect(d.map((e) => e.serial), [
      'ALDE6R2516001927',
      '192.168.1.5:5555',
      'emulator-5554',
    ]);
    expect(d[0].ready, isTrue);
    expect(d[0].model, 'TFY_LX1');
    expect(d[1].wireless, isTrue);
    expect(d[2].ready, isFalse);
  });

  test('serialForForwardedPort matches the VM service port', () {
    const list = 'A tcp:49466 tcp:42339\nB tcp:49597 tcp:40145\n';
    expect(serialForForwardedPort(list, 49597), 'B');
    expect(serialForForwardedPort(list, 1), isNull);
  });

  test('describeAndroidScreen: labelled elements with tap points', () {
    const xml =
        '''<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" content-desc="" clickable="false" enabled="true" bounds="[0,0][1080,2289]"><node index="0" text="Allow Tom &amp; Jerry to access photos?" class="android.widget.TextView" content-desc="" clickable="false" enabled="true" bounds="[100,800][980,900]" /><node index="1" text="Allow" class="android.widget.Button" content-desc="" clickable="true" enabled="true" bounds="[100,1000][500,1100]" /><node index="2" text="" class="android.widget.ImageView" content-desc="Close" clickable="true" enabled="false" bounds="[0,0][100,100]" /></node></hierarchy>
UI hierchary dumped to: /dev/tty''';
    expect(
      describeAndroidScreen(xml),
      '- TextView "Allow Tom & Jerry to access photos?" → tap (540, 850)\n'
      '- Button "Allow" (clickable) → tap (300, 1050)\n'
      '- ImageView "Close" (disabled) (clickable) → tap (50, 50)\n'
      'Coordinates are screen pixels (native_tap).',
    );
    expect(
      parseUiautomatorDump(
        '<node text="&#128100; Ann" class="a.B" bounds="[0,0][2,2]" />',
      ).single.label,
      '\u{1F464} Ann',
    );
    expect(describeAndroidScreen('<hierarchy/>'), contains('Nothing native'));
  });

  test('escapeAdbInputText quotes for the device shell', () {
    expect(escapeAdbInputText('hi there'), "'hi%sthere'");
    expect(escapeAdbInputText('a&b'), r"'a\&b'");
    expect(escapeAdbInputText("it's"), r"'it\'\''s'");
    expect(escapeAdbInputText('héllo'), isNull);
  });

  test('parseAndroidDeviceState: asleep and locked, then fine', () {
    final asleep = parseAndroidDeviceState(
      power: '  mWakefulness=Asleep\n',
      window: '    isKeyguardShowing=true\n',
      battery: '  USB powered: true\n  AC powered: false\n  level: 100\n',
      lowPower: '0\n',
      timeout: '30000\n',
    );
    expect(asleep.problem, 'the screen is off (asleep)');
    expect(asleep.locked, isTrue);
    expect(asleep.charging, isTrue);
    expect(asleep.batteryLevel, 100);
    expect(asleep.batterySaver, isFalse);
    expect(asleep.describe(), contains('screen OFF'));
    expect(asleep.describe(), contains('dims after 30 s'));

    final ok = parseAndroidDeviceState(
      power: 'mWakefulness=Awake',
      window: 'isKeyguardShowing=false',
    );
    expect(ok.problem, isNull);
    final locked = parseAndroidDeviceState(
      power: 'mWakefulness=Awake',
      window: 'isKeyguardShowing=true',
    );
    expect(locked.problem, 'the device is locked');
  });

  test('findAdb prefers PATH, then ANDROID_HOME', () async {
    expect(await findAdb(environment: {}, onPath: (_) async => true), 'adb');
    expect(
      await findAdb(
        environment: {'ANDROID_HOME': '/nope'},
        onPath: (_) async => false,
      ),
      isNull,
    );
  });
}
