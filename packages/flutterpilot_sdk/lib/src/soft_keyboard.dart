import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The on-screen keyboard. On a phone it stays up after typing and covers
/// (or, with a resizing Scaffold, clips) the lower part of the screen: a
/// user closes it before tapping a button under it, and so does FlutterPilot.
class SoftKeyboard {
  /// Whether an on-screen keyboard takes up part of any view.
  static bool get isVisible => WidgetsBinding.instance.platformDispatcher.views
      .any((v) => v.viewInsets.bottom > 0);

  /// Hides the keyboard, keeping focus (what the back gesture does), and
  /// waits until the app has laid out without it. Returns whether it went.
  static Future<bool> hide({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (!isVisible) return false;
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    final deadline = DateTime.now().add(timeout);
    while (isVisible && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (isVisible) return false;
    // One frame so the layout reflects the full-height screen.
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return true;
  }
}
