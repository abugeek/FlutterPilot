import 'dart:ffi';
import 'dart:io';

/// macOS App Nap throttles an app whose window is hidden or covered: its
/// timers slow down and it runs at background priority, so every tool call
/// took 2–3× longer (a tap 400 ms instead of 150 ms). While an agent is
/// working the app holds an NSProcessInfo activity, which App Nap honours —
/// the same thing a video player does while playing.
Pointer<Void> _activity = nullptr;

final _objc = DynamicLibrary.process();
final _getClass = _objc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Uint8>),
      Pointer<Void> Function(Pointer<Uint8>)
    >('objc_getClass');
final _selector = _objc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Uint8>),
      Pointer<Void> Function(Pointer<Uint8>)
    >('sel_registerName');
final _msgSendPtr = _objc.lookup<Void>('objc_msgSend');
final _send0 = _msgSendPtr
    .cast<
      NativeFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>
    >()
    .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>();
final _send1 = _msgSendPtr
    .cast<
      NativeFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >
    >()
    .asFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
    >();
final _sendBegin = _msgSendPtr
    .cast<
      NativeFunction<
        Pointer<Void> Function(
          Pointer<Void>,
          Pointer<Void>,
          Uint64,
          Pointer<Void>,
        )
      >
    >()
    .asFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int, Pointer<Void>)
    >();
final _malloc = _objc
    .lookupFunction<
      Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)
    >('malloc');
final _free = _objc
    .lookupFunction<
      Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)
    >('free');

/// A C string that lives until [_free]d.
Pointer<Uint8> _cString(String s) {
  final bytes = s.codeUnits;
  final p = _malloc(bytes.length + 1);
  for (var i = 0; i < bytes.length; i++) {
    p[i] = bytes[i];
  }
  p[bytes.length] = 0;
  return p;
}

Pointer<Void> _sel(String name) {
  final c = _cString(name);
  try {
    return _selector(c);
  } finally {
    _free(c);
  }
}

Pointer<Void> _class(String name) {
  final c = _cString(name);
  try {
    return _getClass(c);
  } finally {
    _free(c);
  }
}

Pointer<Void> _processInfo() =>
    _send0(_class('NSProcessInfo'), _sel('processInfo'));

/// NSActivityUserInitiatedAllowingIdleSystemSleep | NSActivityLatencyCritical:
/// not napped, timers on time; the Mac may still sleep.
const _options = 0x00EFFFFF | 0xFF00000000;

void beginActivity() {
  if (!Platform.isMacOS || _activity != nullptr) return;
  try {
    final reason = _cString('An agent is driving the app (FlutterPilot)');
    final Pointer<Void> string;
    try {
      string = _send1(
        _class('NSString'),
        _sel('stringWithUTF8String:'),
        reason.cast(),
      );
    } finally {
      _free(reason);
    }
    final activity = _sendBegin(
      _processInfo(),
      _sel('beginActivityWithOptions:reason:'),
      _options,
      string,
    );
    // Returned autoreleased: keep it until endActivity.
    _activity = _send0(activity, _sel('retain'));
  } catch (_) {
    // No Objective-C runtime (a test host): nothing to keep awake.
  }
}

void endActivity() {
  if (_activity == nullptr) return;
  _send1(_processInfo(), _sel('endActivity:'), _activity);
  _send0(_activity, _sel('release'));
  _activity = nullptr;
}
