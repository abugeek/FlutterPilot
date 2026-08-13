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
  });
}
