import 'ring_buffer.dart';
import 'diagnostic_payload.dart';

/// Real-time stream and WebSocket event inspector for FlutterPilot.
///
/// Captures incoming and outgoing real-time messages (WebSockets, Supabase Channels,
/// SSE, EventStreams) into a rolling 100-event ring buffer.
class StreamInspector {
  static const int bufferSize = 100;
  static final RingBuffer<Map<String, dynamic>> _streamBuffer = RingBuffer(bufferSize);

  /// Records an incoming or outgoing stream frame.
  static void recordEvent({
    required String channel,
    required String direction, // 'in' | 'out'
    required dynamic payload,
    String? type,
  }) {
    _streamBuffer.add({
      'channel': channel,
      'direction': direction,
      'type': type ?? 'message',
      'payload': DiagnosticPayload.sanitize(payload),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Returns all buffered stream events as an unmodifiable list.
  static List<Map<String, dynamic>> getEvents({String? channelFilter}) {
    final list = _streamBuffer.toList();
    if (channelFilter == null || channelFilter.isEmpty) {
      return list;
    }
    return list.where((e) => e['channel'] == channelFilter).toList();
  }

  /// Clears the stream log buffer.
  static void clear() {
    _streamBuffer.clear();
  }
}
