import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device screen on while an agent is driving the app, so a real
/// phone does not dim and lock halfway through a test. Released
/// [idleRelease] after the last FlutterPilot call, so the phone sleeps
/// normally once the session is over.
class KeepAwake {
  KeepAwake._();

  static const idleRelease = Duration(minutes: 10);
  static Timer? _release;
  static bool _held = false;

  /// Off with `--dart-define=FLUTTERPILOT_KEEP_AWAKE=false`.
  static const _enabled =
      bool.fromEnvironment('FLUTTERPILOT_KEEP_AWAKE', defaultValue: true);

  /// Called on every agent call: holds the wakelock and pushes the release out.
  static void touch() {
    if (!_enabled || kReleaseMode) return;
    _release?.cancel();
    _release = Timer(idleRelease, _drop);
    if (_held) return;
    _held = true;
    _set(true);
  }

  static void _drop() {
    _release = null;
    if (!_held) return;
    _held = false;
    _set(false);
  }

  // No plugin on this platform or in a unit test: nothing to hold.
  static void _set(bool on) {
    try {
      (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {});
    } catch (_) {}
  }
}
