part of '../../flutterpilot_server.dart';

/// Tools for capturing screenshots, comparing baselines, and inspecting
/// the widget tree, widget properties, and semantics tree.
mixin _ScreenshotToolsMixin on _FlutterPilotServerBase {
  void _registerScreenshotTools() {
    server.registerTool(
      'capture_screenshot',
      description:
          'Capture a vision-ready image of the current screen. CALL THIS to analyze layout, colors, or visual glitches. HINT: Compare with `get_widget_tree` for coordinate-perfect reasoning.',
      inputSchema: ToolInputSchema(
        properties: {
          'format': JsonSchema.string(enumValues: ['png', 'webp']),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.captureScreenshot',
          p,
        );
        if (res.isError) return res.toCallToolResult();
        final imageData = res.data?['data'] as String?;
        if (imageData == null) {
          return CallToolResult(
            content: [TextContent(text: 'Screenshot returned no image data')],
            isError: true,
          );
        }
        return CallToolResult(
          content: [
            ImageContent(data: imageData, mimeType: 'image/png'),
            TextContent(
              text:
                  'Screenshot captured. HINT: If you see an error overlay, call diagnose_last_error immediately.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'save_screenshot_baseline',
      description:
          'Captures the current screen and stores it as a named baseline image for future '
          'visual regression comparisons. Call this once to establish a golden image, then '
          'use compare_screenshot after code changes.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(
            description:
                'A unique name for this baseline image (e.g. "home_screen", "login_dark"). Used to reference it in compare_screenshot.',
          ),
        },
        required: ['name'],
      ),
      callback: (p, e) async {
        final name = p['name']?.toString();
        if (name == null || name.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'name is required')],
            isError: true,
          );
        }
        final res = await _callExtensionRaw(
          'ext.flutterpilot.captureScreenshot',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final base64Str = res.data?['data'] as String?;
        if (base64Str == null) {
          return CallToolResult(
            content: [TextContent(text: 'Screenshot returned no data')],
            isError: true,
          );
        }
        // Evict oldest baseline when at capacity
        if (_screenshotBaselines.length >= _Constants.maxScreenshotBaselines) {
          final firstKey = _screenshotBaselines.keys.firstOrNull;
          if (firstKey != null) {
            _screenshotBaselines.remove(firstKey);
          }
        }
        final Uint8List decoded;
        try {
          decoded = base64Decode(base64Str);
        } on FormatException {
          return CallToolResult(
            content: [TextContent(text: 'Invalid base64 screenshot data')],
            isError: true,
          );
        }
        _screenshotBaselines[name] = decoded;
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Baseline "$name" saved (${_screenshotBaselines[name]!.length} bytes). '
                  'HINT: Run compare_screenshot after making visual changes.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'compare_screenshot',
      description:
          'Captures the current screen and compares it pixel-by-pixel with a previously saved '
          'baseline. Returns the percentage of changed pixels. Use for visual regression testing.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(
            description: 'Baseline name set by save_screenshot_baseline',
          ),
          'threshold': JsonSchema.number(
            description: 'Allowed diff % before test fails (default 1.0 = 1%)',
          ),
        },
        required: ['name'],
      ),
      callback: (p, e) async {
        final name = p['name']?.toString();
        if (name == null || name.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'name is required')],
            isError: true,
          );
        }
        final baseline = _screenshotBaselines[name];
        if (baseline == null) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'No baseline named "$name". '
                    'Call save_screenshot_baseline first.',
              ),
            ],
            isError: true,
          );
        }
        final res = await _callExtensionRaw(
          'ext.flutterpilot.captureScreenshot',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final base64Str = res.data?['data'] as String?;
        if (base64Str == null) {
          return CallToolResult(
            content: [TextContent(text: 'Screenshot returned no data')],
            isError: true,
          );
        }
        final Uint8List currentBytes;
        try {
          currentBytes = base64Decode(base64Str);
        } on FormatException {
          return CallToolResult(
            content: [TextContent(text: 'Invalid base64 screenshot data')],
            isError: true,
          );
        }
        final threshold = (p['threshold'] as num?)?.toDouble() ?? 1.0;

        // Decode both PNGs and compare pixel-by-pixel.
        final baselineImg = img.decodePng(baseline);
        final currentImg = img.decodePng(currentBytes);

        if (baselineImg == null || currentImg == null) {
          return CallToolResult(
            content: [
              TextContent(text: 'Failed to decode PNG images for comparison'),
            ],
            isError: true,
          );
        }

        double diffPercent;
        if (baselineImg.width != currentImg.width ||
            baselineImg.height != currentImg.height) {
          diffPercent = 100.0;
        } else {
          int diffPixels = 0;
          final total = baselineImg.width * baselineImg.height;
          // Early-exit threshold: once we exceed this, stop comparing
          final earlyExitThreshold = (total * (threshold / 100.0) * 1.5).ceil();
          bool earlyExit = false;
          for (int y = 0; y < baselineImg.height && !earlyExit; y++) {
            for (int x = 0; x < baselineImg.width; x++) {
              final bp = baselineImg.getPixel(x, y);
              final cp = currentImg.getPixel(x, y);
              if (bp.r != cp.r || bp.g != cp.g || bp.b != cp.b) {
                diffPixels++;
              }
              if (diffPixels > earlyExitThreshold) {
                earlyExit = true;
                break;
              }
            }
          }
          diffPercent = total > 0 ? (diffPixels / total) * 100.0 : 0.0;
        }

        final passed = diffPercent <= threshold;
        final diffStr = diffPercent.toStringAsFixed(2);
        return CallToolResult(
          content: [
            TextContent(
              text: passed
                  ? 'Visual regression PASSED ✅ — diff: $diffStr% (threshold: $threshold%)'
                  : 'Visual regression FAILED ❌ — diff: $diffStr% exceeds threshold $threshold%',
            ),
          ],
          isError: !passed,
        );
      },
    );

    _registerAppTool(
      name: 'get_widget_tree',
      description:
          'Retrieve the complete widget hierarchy with exact screen coordinates (x, y, width, height) and source code locations (file/line). CALL THIS to locate buttons to tap or to debug layout overflows.',
      extension: 'ext.flutterpilot.getWidgetTree',
      nudge:
          'HINT: You can now use tap_widget(key) or enter_text(key) using the keys found in this tree.',
    );

    server.registerTool(
      'get_widget_properties',
      description:
          'Reads the semantic properties of a widget identified by its key. '
          'Returns: type, text (Text/TextField content), isEnabled '
          '(onPressed/onTap/onChanged non-null), isChecked (Checkbox/Switch), '
          'value/min/max (Slider), isFocused, and screen-space bounds. '
          'Use this instead of screenshots to verify widget state.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The ValueKey string of the widget to inspect.',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getWidgetProperties',
          {'key': p['key'].toString()},
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'get_semantics_tree',
      description:
          'Returns the full accessibility semantics tree as seen by screen '
          'readers (VoiceOver/TalkBack). Each node has: id, label, value, '
          'hint, tooltip, role flags (isButton/isTextField/isSlider/isImage/'
          'isLink/isLiveRegion), isChecked, isEnabled, isFocused, and '
          'screen-space rect. Use this for accessibility audits.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getSemanticsTree',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [TextContent(text: jsonEncode(res.data))],
        );
      },
    );
  }
}
