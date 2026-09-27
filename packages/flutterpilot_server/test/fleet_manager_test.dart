import 'package:flutterpilot_server/src/fleet_manager.dart';
import 'package:test/test.dart';

void main() {
  group('FleetManager', () {
    late FleetManager fleet;

    setUp(() {
      fleet = FleetManager();
    });

    test('registers devices and sets first as active', () {
      expect(fleet.activeDeviceId, isNull);
      fleet.registerDevice('ios_sim', 'ws://127.0.0.1:8181/ws');
      expect(fleet.activeDeviceId, equals('ios_sim'));
      expect(fleet.activeUri, equals('ws://127.0.0.1:8181/ws'));

      fleet.registerDevice('android_emu', 'ws://127.0.0.1:8182/ws');
      expect(fleet.activeDeviceId, equals('ios_sim')); // Still first device
    });

    test('switches active device', () {
      fleet.registerDevice('ios_sim', 'ws://127.0.0.1:8181/ws');
      fleet.registerDevice('android_emu', 'ws://127.0.0.1:8182/ws');

      final switched = fleet.switchDevice('android_emu');
      expect(switched, isTrue);
      expect(fleet.activeDeviceId, equals('android_emu'));
      expect(fleet.activeUri, equals('ws://127.0.0.1:8182/ws'));

      final invalidSwitch = fleet.switchDevice('non_existent');
      expect(invalidSwitch, isFalse);
    });

    test('lists devices correctly', () {
      fleet.registerDevice('device1', 'ws://127.0.0.1:8001/ws');
      fleet.registerDevice('device2', 'ws://127.0.0.1:8002/ws');

      final list = fleet.listDevices();
      expect(list['total'], equals(2));
      expect(list['activeDevice'], equals('device1'));
      final devices = list['devices'] as List;
      expect(devices.length, equals(2));
      expect(devices[0]['isActive'], isTrue);
      expect(devices[1]['isActive'], isFalse);
    });

    test('re-registering the active device replaces its URI (app restart)', () {
      fleet.registerDevice('default', 'ws://127.0.0.1:8001/old=/ws');
      fleet.registerDevice('default', 'ws://127.0.0.1:9002/new=/ws');
      expect(fleet.activeDeviceId, equals('default'));
      expect(fleet.activeUri, equals('ws://127.0.0.1:9002/new=/ws'));
      expect(fleet.listDevices()['total'], equals(1));
    });

    test('registering a known URI under a new name renames that entry', () {
      fleet.registerDevice('default', 'ws://127.0.0.1:8001/a=/ws');
      fleet.registerDevice('web', 'ws://127.0.0.1:8002/b=/ws');
      expect(
        fleet.registerDevice('mac', 'ws://127.0.0.1:8001/a=/ws'),
        'default',
      );
      expect(fleet.activeDeviceId, 'mac');
      expect(fleet.deviceIds, ['web', 'mac']);
      expect(fleet.idForUri('ws://127.0.0.1:8002/b=/ws'), 'web');
    });

    test('describe says what runs where, and which device is gone', () {
      fleet.registerDevice('mac', 'ws://127.0.0.1:8001/secret=/ws');
      fleet.registerDevice('web', 'ws://127.0.0.1:8002/b=/ws');
      final text = fleet.describe({
        'mac': const DeviceInfo(
          platform: 'macos',
          app: 'hn_reader',
          hasSdk: true,
        ),
      });
      expect(
        text,
        contains(
          '- mac (active): macos · hn_reader · flutterpilot_sdk — 127.0.0.1:8001',
        ),
      );
      expect(text, contains('- web: not running'));
      expect(text, isNot(contains('secret')));
    });
  });

  test('normalizeVmServiceUri accepts what flutter run and DevTools print', () {
    const ws = 'ws://127.0.0.1:49588/0ZnhG9AjJsM=/ws';
    expect(normalizeVmServiceUri(ws), ws);
    expect(normalizeVmServiceUri('http://127.0.0.1:49588/0ZnhG9AjJsM=/'), ws);
    expect(normalizeVmServiceUri(' http://127.0.0.1:49588/0ZnhG9AjJsM= '), ws);
    expect(
      normalizeVmServiceUri('http://127.0.0.1:9100/devtools/?uri=$ws'),
      ws,
    );
    expect(normalizeVmServiceUri('pixel_8'), isNull);
    expect(normalizeVmServiceUri('file:///tmp/x'), isNull);
  });
}
