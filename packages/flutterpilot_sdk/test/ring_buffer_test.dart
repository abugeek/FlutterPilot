import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_sdk/src/ring_buffer.dart';

void main() {
  group('RingBuffer Tests', () {
    test('Stores and retrieves elements in FIFO order', () {
      final buffer = RingBuffer<int>(3);
      expect(buffer.isEmpty, isTrue);

      buffer.add(1);
      buffer.add(2);
      expect(buffer.length, equals(2));
      expect(buffer[0], equals(1));
      expect(buffer[1], equals(2));
    });

    test('Evicts oldest elements automatically in O(1) time without array copy', () {
      final buffer = RingBuffer<String>(3);
      buffer.add('a');
      buffer.add('b');
      buffer.add('c');
      expect(buffer.toList(), equals(['a', 'b', 'c']));

      // Adding 4th element evicts 'a'
      buffer.add('d');
      expect(buffer.length, equals(3));
      expect(buffer.toList(), equals(['b', 'c', 'd']));

      // Adding 5th element evicts 'b'
      buffer.add('e');
      expect(buffer.length, equals(3));
      expect(buffer.toList(), equals(['c', 'd', 'e']));
    });

    test('Iterates cleanly over elements', () {
      final buffer = RingBuffer<int>(2);
      buffer.add(10);
      buffer.add(20);
      buffer.add(30);

      final collected = <int>[];
      for (final item in buffer) {
        collected.add(item);
      }
      expect(collected, equals([20, 30]));
    });

    test('Clears buffer in O(1)', () {
      final buffer = RingBuffer<int>(5);
      buffer.addAll([1, 2, 3]);
      expect(buffer.length, equals(3));

      buffer.clear();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, equals(0));
    });
  });
}
