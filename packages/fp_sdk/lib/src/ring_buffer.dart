import 'dart:collection';

/// High-performance fixed-capacity circular ring buffer with O(1) insertion,
/// zero memory shifting, and FIFO eviction.
class RingBuffer<T> with IterableMixin<T> {
  RingBuffer(this.capacity)
    : assert(capacity > 0, 'Capacity must be positive'),
      _buffer = List<T?>.filled(capacity, null);

  /// Maximum number of items the buffer can hold.
  final int capacity;

  final List<T?> _buffer;
  int _start = 0;
  int _count = 0;

  @override
  int get length => _count;

  @override
  bool get isEmpty => _count == 0;

  @override
  bool get isNotEmpty => _count > 0;

  /// Adds an element to the buffer in O(1) time.
  /// If the buffer is full, the oldest element is evicted automatically.
  void add(T element) {
    if (_count < capacity) {
      final index = (_start + _count) % capacity;
      _buffer[index] = element;
      _count++;
    } else {
      _buffer[_start] = element;
      _start = (_start + 1) % capacity;
    }
  }

  /// Adds all elements from [iterable].
  void addAll(Iterable<T> iterable) {
    for (final element in iterable) {
      add(element);
    }
  }

  /// Removes and returns the oldest element in O(1) time.
  T removeFirst() {
    if (_count == 0) throw StateError('Cannot remove from an empty buffer');
    final value = _buffer[_start] as T;
    _buffer[_start] = null;
    _start = (_start + 1) % capacity;
    _count--;
    return value;
  }

  /// Clears all elements from the buffer in O(1) time.
  void clear() {
    _buffer.fillRange(0, capacity, null);
    _start = 0;
    _count = 0;
  }

  /// Returns the element at [index] (0 is the oldest element).
  T operator [](int index) {
    if (index < 0 || index >= _count) {
      throw RangeError.index(
        index,
        this,
        'index',
        'Index out of bounds',
        _count,
      );
    }
    return _buffer[(_start + index) % capacity] as T;
  }

  @override
  Iterator<T> get iterator => _RingBufferIterator<T>(this);

  /// Returns a snapshot list of current elements from oldest to newest.
  @override
  List<T> toList({bool growable = false}) {
    final list = <T>[];
    for (int i = 0; i < _count; i++) {
      list.add(_buffer[(_start + i) % capacity] as T);
    }
    return list;
  }
}

class _RingBufferIterator<T> implements Iterator<T> {
  _RingBufferIterator(this._buffer) : _index = -1;

  final RingBuffer<T> _buffer;
  int _index;

  @override
  T get current {
    if (_index < 0 || _index >= _buffer.length) {
      throw StateError('No current element');
    }
    return _buffer[_index];
  }

  @override
  bool moveNext() {
    if (_index + 1 < _buffer.length) {
      _index++;
      return true;
    }
    return false;
  }
}
