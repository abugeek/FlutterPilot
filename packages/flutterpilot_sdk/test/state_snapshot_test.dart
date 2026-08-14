import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/navigation_tracker.dart';
import 'package:flutterpilot_sdk/src/state_snapshot_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StateSnapshotManager', () {
    setUp(() {
      StateSnapshotManager.clear();
      NavigationTracker.reset();
      StateSnapshotManager.onCaptureStates = null;
      StateSnapshotManager.onRestoreStates = null;
      StateSnapshotManager.onCaptureStorage = null;
      StateSnapshotManager.onRestoreStorage = null;
      StateSnapshotManager.onRestoreNavigation = null;
    });

    test('saves named state snapshot with route and state values', () {
      final mockState = {'riverpod:counter': 42, 'bloc:theme': 'dark'};
      StateSnapshotManager.onCaptureStates = () => mockState;

      final snapshot = StateSnapshotManager.saveSnapshot('test_checkout');
      expect(snapshot.name, equals('test_checkout'));
      expect(snapshot.states['riverpod:counter'], equals(42));
      expect(snapshot.states['bloc:theme'], equals('dark'));

      final list = StateSnapshotManager.listSnapshots();
      expect(list.length, equals(1));
      expect(list.first['name'], equals('test_checkout'));
    });

    testWidgets('restores named state snapshot and executes restore delegate', (
      tester,
    ) async {
      final mockState = {'riverpod:counter': 100};
      StateSnapshotManager.onCaptureStates = () => mockState;
      StateSnapshotManager.saveSnapshot('snap_100');

      Map<String, dynamic>? restoredData;
      StateSnapshotManager.onRestoreStates = (states) async {
        restoredData = states;
      };

      final success = await StateSnapshotManager.restoreSnapshot('snap_100');
      expect(success, isTrue);
      expect(restoredData, isNotNull);
      expect(restoredData!['riverpod:counter'], equals(100));

      final failed = await StateSnapshotManager.restoreSnapshot('non_existent');
      expect(failed, isFalse);
    });

    test('deletes snapshot by name', () {
      StateSnapshotManager.saveSnapshot('snap_a');
      StateSnapshotManager.saveSnapshot('snap_b');
      expect(StateSnapshotManager.listSnapshots().length, equals(2));

      final deleted = StateSnapshotManager.deleteSnapshot('snap_a');
      expect(deleted, isTrue);
      expect(StateSnapshotManager.listSnapshots().length, equals(1));
      expect(
        StateSnapshotManager.listSnapshots().first['name'],
        equals('snap_b'),
      );
    });

    test('exports and imports snapshots JSON', () {
      StateSnapshotManager.onCaptureStates = () => {'key': 'value123'};
      StateSnapshotManager.saveSnapshot('export_test');

      final exportedJson = StateSnapshotManager.exportJson();
      expect(exportedJson, contains('export_test'));
      expect(exportedJson, contains('value123'));

      StateSnapshotManager.clear();
      expect(StateSnapshotManager.listSnapshots().isEmpty, isTrue);

      final count = StateSnapshotManager.importJson(exportedJson);
      expect(count, equals(1));
      expect(StateSnapshotManager.listSnapshots().length, equals(1));
      expect(StateSnapshotManager.getSnapshot('export_test'), isNotNull);
    });

    test('captures and restores storage and navigation delegates', () async {
      StateSnapshotManager.onCaptureStates = () => {'state': 1};
      StateSnapshotManager.onCaptureStorage = () => {'session': 'test'};
      final snapshot = StateSnapshotManager.saveSnapshot('complete');

      expect(snapshot.storage['session'], equals('test'));

      Map<String, dynamic>? restoredStorage;
      String? restoredRoute;
      List<String>? restoredStack;
      StateSnapshotManager.onRestoreStorage = (storage) async {
        restoredStorage = storage;
      };
      StateSnapshotManager.onRestoreNavigation = (route, stack) async {
        restoredRoute = route;
        restoredStack = stack;
      };

      expect(await StateSnapshotManager.restoreSnapshot('complete'), isTrue);
      expect(restoredStorage, equals({'session': 'test'}));
      expect(restoredRoute, equals('Unknown'));
      expect(restoredStack, isEmpty);
    });

    test('converts sets and custom values to JSON-safe snapshot values', () {
      StateSnapshotManager.onCaptureStates = () => {
        'set': {'a', 'b'},
        'date': DateTime.utc(2026, 1, 1),
        'custom': Object(),
      };
      StateSnapshotManager.saveSnapshot('json_safe');

      expect(() => StateSnapshotManager.exportJson(), returnsNormally);
    });
  });
}
