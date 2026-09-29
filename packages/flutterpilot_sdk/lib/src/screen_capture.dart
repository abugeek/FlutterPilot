import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'ai_overlay_manager.dart';

/// The app's window as the user sees it: every route, dialog, menu and
/// sheet, without FlutterPilot's tap badge.
///
/// Captured from the view's root layer. The first repaint boundary below it
/// is only the bottom route's page: a dialog on the root navigator, or any
/// popup in an app with one navigator, would be missing from the picture.
class ScreenCapture {
  /// The window at [pixelRatio] image pixels per logical pixel, or null
  /// before the first frame.
  static Future<ui.Image?> image({double pixelRatio = 1.0}) async {
    await settle();
    return grab(pixelRatio: pixelRatio);
  }

  /// Removes the tap badge and waits for the frame that takes it off the
  /// screen, or that paints any other change still waiting for one: the root
  /// layer holds the last frame. Frames are forced, so this works while the
  /// window is hidden.
  static Future<void> settle() async {
    final cleared = AiOverlayManager.clearNow();
    if (!cleared && !SchedulerBinding.instance.hasScheduledFrame) return;
    final done = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!done.isCompleted) done.complete();
    });
    SchedulerBinding.instance.scheduleForcedFrame();
    await done.future.timeout(
      const Duration(milliseconds: 250),
      onTimeout: () {},
    );
  }

  /// The last frame as painted, without waiting.
  static Future<ui.Image?> grab({double pixelRatio = 1.0}) async {
    final view = RendererBinding.instance.renderViews.firstOrNull;
    // Reading the root layer is what flutter_test's matchesGoldenFile does.
    // ignore: invalid_use_of_protected_member
    final layer = view?.layer;
    if (view == null || layer is! OffsetLayer || view.paintBounds.isEmpty) {
      return null;
    }
    // The root layer scales logical pixels to physical ones itself, and
    // paintBounds is in physical pixels.
    return layer.toImage(
      view.paintBounds,
      pixelRatio: pixelRatio / view.configuration.devicePixelRatio,
    );
  }
}
