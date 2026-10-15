import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'redaction.dart';

/// The binding [PlatformChannelMocks.install] creates when the app has none
/// yet: a [WidgetsFlutterBinding] whose messenger lets FlutterPilot answer
/// platform-channel calls (a plugin's camera, location, permission) in the
/// native side's place.
class FlutterPilotBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      PlatformChannelMocks.wrap(super.createBinaryMessenger());
}

/// One call the app made on a platform channel.
class PlatformCall {
  PlatformCall(this.channel, this.method, this.arguments);

  final String channel;

  /// Null on a message channel (Pigeon: the method is in the channel name).
  final String? method;
  final String arguments;

  /// `mocked`, `answered` (by the platform), `no plugin` (nothing on this
  /// platform implements the channel) or `pending`.
  String outcome = 'pending';
}

/// Answers the app's platform-channel calls with canned values and delivers
/// platform events to it, so plugin-backed features (a barcode scan, a
/// location fix, a denied permission) can be driven without the hardware.
class PlatformChannelMocks {
  static const _standard = StandardMethodCodec();
  static const _json = JSONMethodCodec();
  static const _maxCalls = 200;
  static const _pigeon = 'dev.flutter.pigeon.';

  static bool _installed = false;
  static final _mocks = <String, Map<String, Object?>>{};
  static final _calls = ListQueue<PlatformCall>();
  static final _listening = <String>{};
  static final _jsonChannels = <String>{};

  /// Whether the app's outgoing calls go through FlutterPilot (mocks can
  /// answer them, and they are listed).
  static bool get installed => _installed;

  /// Creates [FlutterPilotBinding] unless the app already has a binding (it
  /// called `WidgetsFlutterBinding.ensureInitialized()` first, or runs under
  /// a test binding): outgoing calls can then not be mocked.
  static void install() {
    if (_installed) return;
    try {
      WidgetsBinding.instance;
    } catch (_) {
      FlutterPilotBinding();
    }
  }

  /// The messenger [FlutterPilotBinding] uses.
  static BinaryMessenger wrap(BinaryMessenger inner) {
    _installed = true;
    return _Messenger(inner);
  }

  @visibleForTesting
  static void debugReset() {
    _mocks.clear();
    _calls.clear();
    _jsonChannels.clear();
  }

  static String _id(String channel, String? method) =>
      method == null ? channel : '$channel#$method';

  /// Answers calls to [method] on [channel] (every call when null: a
  /// message channel) with [result], or with a PlatformException when
  /// [errorCode] is set.
  static void mock(
    String channel, {
    String? method,
    Object? result,
    String? errorCode,
    String? errorMessage,
  }) {
    _mocks[_id(channel, method)] = {
      'channel': channel,
      'method': ?method,
      if (errorCode == null) 'result': result,
      'errorCode': ?errorCode,
      'errorMessage': ?errorMessage,
    };
  }

  /// Removes the mocks of [channel] (its [method] only, when given), or all.
  static int clear({String? channel, String? method}) {
    final before = _mocks.length;
    _mocks.removeWhere(
      (_, m) =>
          (channel == null || m['channel'] == channel) &&
          (method == null || m['method'] == method),
    );
    return before - _mocks.length;
  }

  static List<Map<String, Object?>> get mocks => _mocks.values.toList();

  /// The plugin channels the app has a handler on (EventChannel streams,
  /// method-call handlers), not Flutter's own.
  static List<String> get listeners => [
    for (final c in _listening)
      if (!c.startsWith('flutter/')) c,
  ];

  /// The app's recent calls, one per channel and method, newest last.
  static List<Map<String, Object?>> get calls {
    final grouped = <String, Map<String, Object?>>{};
    for (final c in _calls) {
      final id = _id(c.channel, c.method);
      final times = (grouped.remove(id)?['times'] as int? ?? 0) + 1;
      grouped[id] = {
        'channel': c.channel,
        'method': ?c.method,
        'arguments': c.arguments,
        'outcome': c.outcome,
        'times': times,
      };
    }
    return grouped.values.toList();
  }

  /// Delivers [event] to the listeners of the EventChannel [channel] as the
  /// platform would (an error event when [errorCode] is set). Returns
  /// whether the app listens to the channel: true, false (the event waits
  /// for a listener), or null when that can't be told ([installed] false).
  static bool? emit(
    String channel,
    Object? event, {
    String? errorCode,
    String? errorMessage,
  }) {
    final MethodCodec codec = _jsonChannels.contains(channel)
        ? _json
        : _standard;
    final data = errorCode != null
        ? codec.encodeErrorEnvelope(code: errorCode, message: errorMessage)
        : codec.encodeSuccessEnvelope(fromJson(event));
    ui.channelBuffers.push(channel, data, (_) {});
    return _installed ? _listening.contains(channel) : null;
  }

  /// JSON as a platform would send it: `{"$bytes": base64}` is a Uint8List.
  static Object? fromJson(Object? v) => switch (v) {
    Map() when v.length == 1 && v[r'$bytes'] is String => base64.decode(
      v[r'$bytes'] as String,
    ),
    Map() => {for (final e in v.entries) e.key: fromJson(e.value)},
    List() => [for (final x in v) fromJson(x)],
    _ => v,
  };

  static String _describe(Object? arguments) {
    if (arguments == null) return '';
    String text;
    try {
      text = json.encode(
        arguments,
        toEncodable: (o) =>
            o is TypedData ? '<${o.lengthInBytes} bytes>' : '$o',
      );
    } catch (_) {
      text = '$arguments';
    }
    text = Redaction.text(text);
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }

  /// The reply to a message the app sends, when a mock covers it; null to
  /// let the platform answer. Records the call (not Flutter's own
  /// `flutter/…` channels: text input, cursors, haptics).
  static ({bool mocked, ByteData? reply, PlatformCall? call}) _intercept(
    String channel,
    ByteData? message,
  ) {
    MethodCall? call;
    MethodCodec? codec;
    Object? payload;
    if (message != null) {
      try {
        call = _standard.decodeMethodCall(message);
        codec = _standard;
      } catch (_) {
        try {
          call = _json.decodeMethodCall(message);
          codec = _json;
          _jsonChannels.add(channel);
        } catch (_) {
          try {
            payload = const StandardMessageCodec().decodeMessage(message);
          } catch (_) {
            payload = '<${message.lengthInBytes} bytes>';
          }
        }
      }
    }
    final mock = _mocks[_id(channel, call?.method)] ?? _mocks[channel];
    PlatformCall? record;
    if (!channel.startsWith('flutter/')) {
      record = PlatformCall(
        channel,
        call?.method,
        _describe(call == null ? payload : call.arguments),
      );
      _calls.add(record);
      if (_calls.length > _maxCalls) _calls.removeFirst();
    }
    if (mock == null) return (mocked: false, reply: null, call: record);
    record?.outcome = 'mocked';

    final code = mock['errorCode'] as String?;
    final message_ = mock['errorMessage'] as String?;
    final result = fromJson(mock['result']);
    if (codec != null) {
      return (
        mocked: true,
        reply: code != null
            ? codec.encodeErrorEnvelope(code: code, message: message_)
            : codec.encodeSuccessEnvelope(result),
        call: record,
      );
    }
    // A message channel. Pigeon replies with [result], or [code, message,
    // details] for an error.
    final Object? reply = channel.startsWith(_pigeon)
        ? (code != null ? [code, message_, null] : [result])
        : result;
    return (
      mocked: true,
      reply: const StandardMessageCodec().encodeMessage(reply),
      call: record,
    );
  }
}

class _Messenger extends BinaryMessenger {
  const _Messenger(this._inner);

  final BinaryMessenger _inner;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    final hit = PlatformChannelMocks._intercept(channel, message);
    if (hit.mocked) return Future.value(hit.reply);
    final call = hit.call;
    final sent = _inner.send(channel, message);
    if (call == null || sent == null) return sent;
    return sent.then((reply) {
      call.outcome = reply == null ? 'no plugin' : 'answered';
      return reply;
    });
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    if (handler == null) {
      PlatformChannelMocks._listening.remove(channel);
    } else {
      PlatformChannelMocks._listening.add(channel);
    }
    _inner.setMessageHandler(channel, handler);
  }

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) =>
      // ignore: deprecated_member_use
      _inner.handlePlatformMessage(channel, data, callback);
}
