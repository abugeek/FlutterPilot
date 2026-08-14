import 'ring_buffer.dart';
import 'diagnostic_payload.dart';

/// Represents a discrete event captured by the Flight Recorder.
class FlightEvent {
  final String category; // 'gesture', 'route', 'state', 'network', 'error'
  final String action;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  FlightEvent({
    required this.category,
    required this.action,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson({DateTime? baseTimestamp}) {
    final offsetMs = baseTimestamp != null
        ? timestamp.difference(baseTimestamp).inMilliseconds
        : 0;
    return {
      'category': category,
      'action': action,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'offsetMs': offsetMs >= 0 ? '+$offsetMs ms' : '$offsetMs ms',
    };
  }
}

/// Continuous rolling Flight Recorder that captures user actions, state changes,
/// network calls, and route transitions to enable autonomous bug reproduction.
class FlightRecorder {
  static const int maxEvents = 100;
  static final RingBuffer<FlightEvent> _events = RingBuffer<FlightEvent>(maxEvents);
  static List<FlightEvent>? _frozenCrashSnapshot;
  static DateTime? _crashTime;
  static String? _lastException;

  /// Records a flight event into the rolling circular buffer in O(1) time.
  static void record(
    String category,
    String action, [
    Map<String, dynamic>? data,
  ]) {
    _events.add(
      FlightEvent(
        category: category,
        action: action,
        data: DiagnosticPayload.boundedMap(data ?? {}),
      ),
    );
  }

  /// Records a user or AI gesture.
  static void recordGesture(String action, Map<String, dynamic> data) {
    record('gesture', action, data);
  }

  /// Records a route navigation event.
  static void recordRoute(String action, Map<String, dynamic> data) {
    record('route', action, data);
  }

  /// Records a state mutation.
  static void recordState(String source, String name, dynamic value) {
    record('state', '$source:$name', {'value': value});
  }

  /// Records an HTTP network call.
  static void recordNetwork(String type, Map<String, dynamic> data) {
    record('network', type, data);
  }

  /// Captures and freezes the flight log at the moment of a crash.
  static void recordError(String exception, [String? stackTrace]) {
    _lastException = exception;
    _crashTime = DateTime.now();
    record('error', 'unhandled_exception', {
      'exception': exception,
      if (stackTrace != null) 'stackTrace': stackTrace,
    });
    // Freeze the snapshot for reproduction
    _frozenCrashSnapshot = List.unmodifiable(_events.toList());
  }

  /// Returns the current flight log timeline as a list of JSON objects.
  static List<Map<String, dynamic>> getTimeline({bool useFrozen = false}) {
    final list = (useFrozen && _frozenCrashSnapshot != null)
        ? _frozenCrashSnapshot!
        : _events.toList();

    if (list.isEmpty) return [];
    final baseTime = list.first.timestamp;

    return list.map((e) => e.toJson(baseTimestamp: baseTime)).toList();
  }

  /// Returns full flight log status and timeline JSON.
  static Map<String, dynamic> getFlightLogJson() {
    return {
      'totalEvents': _events.length,
      'hasCrashSnapshot': _frozenCrashSnapshot != null,
      'lastException': _lastException,
      'crashTime': _crashTime?.toIso8601String(),
      'timeline': getTimeline(useFrozen: _frozenCrashSnapshot != null),
    };
  }

  /// Clears the flight log buffer and frozen snapshots.
  static void clear() {
    _events.clear();
    _frozenCrashSnapshot = null;
    _crashTime = null;
    _lastException = null;
  }

  /// Returns raw frozen snapshot events if any, or current events.
  static List<FlightEvent> getSnapshotEvents() {
    if (_frozenCrashSnapshot != null && _frozenCrashSnapshot!.isNotEmpty) {
      return _frozenCrashSnapshot!;
    }
    return _events.toList();
  }
}
