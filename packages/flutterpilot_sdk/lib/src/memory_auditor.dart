import 'package:flutter/widgets.dart';

/// Audits memory usage, image cache health, and detects oversized image allocations.
class MemoryAuditor {
  /// Performs a memory and resource audit of the running Flutter application.
  static Map<String, dynamic> audit() {
    final imageCache = PaintingBinding.instance.imageCache;
    final cachedImagesCount = imageCache.currentSize;
    final cachedBytes = imageCache.currentSizeBytes;
    final maxBytes = imageCache.maximumSizeBytes;

    final List<Map<String, dynamic>> warnings = [];

    // Scan widget tree for image widgets
    final root = WidgetsBinding.instance.rootElement;
    if (root != null) {
      void inspectImages(Element element) {
        final w = element.widget;
        if (w is Image) {
          final ro = element.renderObject;
          if (ro is RenderBox && ro.hasSize) {
            final renderedSize = ro.size;
            // Check if Image specifies an unusually large fixed decode width/height compared to layout
            final width = w.width;
            if (width != null && renderedSize.width > 0 && width > renderedSize.width * 4) {
              warnings.add({
                'type': 'Image',
                'issue': 'Image decode width ($width) is >4x larger than rendered layout width (${renderedSize.width.round()}). Consider using cacheWidth.',
              });
            }
          }
        }
        element.visitChildren(inspectImages);
      }

      inspectImages(root);
    }

    final isHealthy = cachedBytes < (maxBytes * 0.8) && warnings.isEmpty;

    return {
      'isHealthy': isHealthy,
      'imageCache': {
        'cachedImagesCount': cachedImagesCount,
        'cachedBytes': cachedBytes,
        'cachedMegaBytes': (cachedBytes / (1024 * 1024)).toStringAsFixed(2),
        'maxMegaBytes': (maxBytes / (1024 * 1024)).toStringAsFixed(2),
      },
      'warningsCount': warnings.length,
      'warnings': warnings,
    };
  }
}
