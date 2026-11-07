import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Set-of-Mark (SoM) visual intelligence registry and canvas badge renderer.
///
/// Overlays numbered badges (1, 2, 3...) at the center or bounding box of
/// interactive elements visible on screen, allowing AI agents to navigate
/// and interact with zero coordinate guessing or selector ambiguity.
class SetOfMark {
  /// Active marks captured during the last labeled screenshot.
  static final List<Map<String, dynamic>> activeMarks = [];

  /// Look up a mark by its 1-based index.
  static Map<String, dynamic>? findByIndex(int index) {
    if (index <= 0 || index > activeMarks.length) return null;
    return activeMarks[index - 1];
  }

  /// Clears active marks.
  static void clear() {
    activeMarks.clear();
  }

  /// Overlays high-contrast numeric badges on top of [baseImage] at the
  /// locations of [interactiveElements].
  static Future<ui.Image> overlayMarks(
    ui.Image baseImage,
    List<Map<String, dynamic>> interactiveElements, {
    double pixelRatio = 1.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Draw base screenshot
    canvas.drawImage(baseImage, Offset.zero, Paint());

    // 2. Prepare marks
    activeMarks.clear();
    var markIndex = 1;

    for (final el in interactiveElements) {
      final bounds = el['bounds'] as Map<String, dynamic>?;
      if (bounds == null) continue;
      final bx = (bounds['x'] as num).toDouble() * pixelRatio;
      final by = (bounds['y'] as num).toDouble() * pixelRatio;

      final markId = markIndex++;
      final centerX =
          (bounds['x'] as num).toDouble() +
          (bounds['width'] as num).toDouble() / 2;
      final centerY =
          (bounds['y'] as num).toDouble() +
          (bounds['height'] as num).toDouble() / 2;

      activeMarks.add({
        'mark': markId,
        'type': el['type'],
        'key': el['key'],
        'text': el['text'],
        'bounds': bounds,
        'center': {'x': centerX, 'y': centerY},
      });

      // Draw badge pill
      final label = '$markId';
      const badgeFontSize = 10.0;
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: badgeFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final padH = 4.0 * pixelRatio;
      final padV = 2.0 * pixelRatio;
      final pillWidth = textPainter.width + padH * 2;
      final pillHeight = textPainter.height + padV * 2;

      final badgeX = bx.clamp(2.0, (baseImage.width - pillWidth - 2).toDouble());
      final badgeY = by.clamp(2.0, (baseImage.height - pillHeight - 2).toDouble());

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(badgeX, badgeY, pillWidth, pillHeight),
        Radius.circular(4.0 * pixelRatio),
      );

      // Crimson background with crisp white border for maximum contrast
      final bgPaint = Paint()
        ..color = const Color(0xFFD32F2F)
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * pixelRatio;

      canvas.drawRRect(rrect, bgPaint);
      canvas.drawRRect(rrect, borderPaint);

      textPainter.paint(canvas, Offset(badgeX + padH, badgeY + padV));
    }

    final picture = recorder.endRecording();
    return picture.toImage(baseImage.width, baseImage.height);
  }
}
