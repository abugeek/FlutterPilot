import 'package:flutterpilot_cli/src/devices_check.dart';
import 'package:test/test.dart';

void main() {
  test('parseAdbList reads state and model', () {
    final d = parseAdbList(
      'List of devices attached\n'
      'ABC  device usb:1 product:X model:TFY_LX1 device:Y\n'
      'DEF  unauthorized usb:2\n',
    );
    expect(d.map((e) => e.state), ['device', 'unauthorized']);
    expect(d.first.model, 'TFY_LX1');
  });

  test('an unauthorized or offline phone is a problem with a fix', () {
    final c = androidChecks(const AdbEntry('S', 'unauthorized', 'M')).single;
    expect(c.ok, isFalse);
    expect(c.fix, contains('Allow USB debugging'));
    expect(
      androidChecks(const AdbEntry('S', 'offline', null)).single.ok,
      isFalse,
    );
  });

  test('an asleep, locked phone with battery saver and a short timeout', () {
    final checks = androidChecks(
      const AdbEntry('S', 'device', 'TFY_LX1'),
      power: 'mWakefulness=Asleep',
      window: 'isKeyguardShowing=true',
      battery: 'level: 80',
      lowPower: '1\n',
      timeout: '30000\n',
    );
    expect(checks, hasLength(3));
    expect(checks[0].warn, isTrue);
    expect(checks[0].title, contains('the screen is off and it is locked'));
    expect(checks[1].title, contains('battery saver'));
    expect(checks[2].title, contains('dims after 30 s'));
    expect(checks.every((c) => c.ok), isTrue, reason: 'advice, not failures');
  });

  test('an awake unlocked phone is fine', () {
    final checks = androidChecks(
      const AdbEntry('S', 'device', 'M'),
      power: 'mWakefulness=Awake',
      window: 'isKeyguardShowing=false',
      battery: 'level: 55',
      lowPower: '0',
      timeout: '600000',
    );
    expect(checks.single.title, contains('screen on, unlocked, battery 55%'));
    expect(checks.single.warn, isFalse);
  });

  test('iPhones: simulators skipped, developer mode, lock state', () {
    String device(String id, String transport, String tunnel, String dev) =>
        '{"identifier":"$id","deviceProperties":{"name":"N$id",'
        '"developerModeStatus":"$dev"},"connectionProperties":'
        '{"transportType":"$transport","tunnelState":"$tunnel"}}';
    final json =
        '{"result":{"devices":[${device('sim', 'sameMachine', 'connected', 'enabled')},'
        '${device('a', 'wired', 'connected', 'enabled')},'
        '${device('b', 'wired', 'connected', 'disabled')},'
        '${device('c', 'localNetwork', 'disconnected', 'enabled')}]}}';
    final checks = iosChecks(json, lockState: (id) => id == 'a');
    expect(checks, hasLength(3));
    expect(checks[0].title, contains('it is locked'));
    expect(checks[1].ok, isFalse);
    expect(checks[1].fix, contains('Developer Mode'));
    expect(checks[2].title, contains('not connected'));
    expect(iosChecks('garbage'), isEmpty);
  });

  test('stale adb forwards: the ones that do not answer', () {
    const list = 'A tcp:1 tcp:9\nA tcp:2 tcp:8\nB tcp:3 tcp:7\nA tcp:4 tcp:6\n';
    expect(staleForwardPorts(list, 'A', {2}), [1, 4]);
    expect(staleForwardPorts(list, 'B', {3}), isEmpty);
    expect(staleForwardChecks('A', const []), isEmpty);
    final c = staleForwardChecks('A', [1, 4]).single;
    expect(c.ok, isTrue);
    expect(c.title, contains('2 stale adb forwards'));
    expect(c.fix, contains('adb -s A forward --remove tcp:1'));
  });
}
