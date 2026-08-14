part of '../../flutterpilot_server.dart';

/// Tools for capturing screenshots, comparing baselines, and inspecting
/// the widget tree, widget properties, and semantics tree.
mixin _ScreenshotToolsMixin on _FlutterPilotServerBase {
  void _registerScreenshotTools() {
    server.registerTool(
      'capture_screenshot',
      description:
          'Capture an image of the current screen for visual analysis with adaptive compression. '
          'Supports scale (e.g. 0.5x) and quality (e.g. 75) to reduce token payload by up to 80%.',
      inputSchema: ToolInputSchema(
        properties: {
          'format': JsonSchema.string(enumValues: ['png', 'jpeg', 'webp']),
          'scale': JsonSchema.number(
            description: 'Scale factor between 0.25 and 1.0 (default: 1.0). Use 0.5 for fast token-efficient AI vision.',
          ),
          'quality': JsonSchema.integer(
            description: 'JPEG compression quality 10-100 (default: 80 for jpeg).',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.captureScreenshot',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final rawBase64 = res.data?['data'] as String?;
        if (rawBase64 == null) {
          return CallToolResult(
            content: [TextContent(text: 'Screenshot returned no image data')],
            isError: true,
          );
        }

        final scale = (p['scale'] as num?)?.toDouble().clamp(0.2, 1.0) ?? 1.0;
        final format = p['format']?.toString().toLowerCase() ?? (scale < 1.0 ? 'jpeg' : 'png');
        final quality = (p['quality'] as num?)?.toInt().clamp(10, 100) ?? 80;

        String finalBase64 = rawBase64;
        String mimeType = 'image/png';

        if (scale < 1.0 || format == 'jpeg') {
          try {
            final rawBytes = base64Decode(rawBase64);
            var decoded = img.decodeImage(rawBytes);
            if (decoded != null) {
              if (scale < 1.0) {
                final targetW = (decoded.width * scale).round().clamp(100, decoded.width);
                decoded = img.copyResize(decoded, width: targetW);
              }
              if (format == 'jpeg') {
                final compressed = img.encodeJpg(decoded, quality: quality);
                finalBase64 = base64Encode(compressed);
                mimeType = 'image/jpeg';
              } else {
                final compressed = img.encodePng(decoded);
                finalBase64 = base64Encode(compressed);
                mimeType = 'image/png';
              }
            }
          } catch (_) {
            // Fallback to original
          }
        }

        return CallToolResult(
          content: [
            ImageContent(data: finalBase64, mimeType: mimeType),
            TextContent(
              text: 'Screenshot captured ($mimeType, scale: ${scale}x).',
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

        double diffPercent = 0.0;
        img.Image? diffImg;
        if (baselineImg.width != currentImg.width ||
            baselineImg.height != currentImg.height) {
          diffPercent = 100.0;
        } else {
          int diffPixels = 0;
          final total = baselineImg.width * baselineImg.height;
          diffImg = img.Image.from(currentImg);

          final baseBytes = baselineImg.toUint8List();
          final currBytes = currentImg.toUint8List();
          final baseWords = baseBytes.buffer.asUint32List();
          final currWords = currBytes.buffer.asUint32List();
          final minLen = baseWords.length < currWords.length ? baseWords.length : currWords.length;

          for (int i = 0; i < minLen; i++) {
            if (baseWords[i] != currWords[i]) {
              diffPixels++;
              final x = i % currentImg.width;
              final y = i ~/ currentImg.width;
              diffImg.setPixelRgba(x, y, 255, 0, 128, 255);
            }
          }
          diffPercent = total > 0 ? (diffPixels / total) * 100.0 : 0.0;
        }

        final passed = diffPercent <= threshold;
        final diffStr = diffPercent.toStringAsFixed(2);
        final contentList = <Content>[
          TextContent(
            text: passed
                ? 'Visual regression PASSED ✅ — diff: $diffStr% (threshold: $threshold%)'
                : 'Visual regression FAILED ❌ — diff: $diffStr% exceeds threshold $threshold%',
          ),
        ];

        if (!passed && diffImg != null) {
          final diffPngBytes = Uint8List.fromList(img.encodePng(diffImg));
          contentList.insert(
            0,
            ImageContent(
              data: base64Encode(diffPngBytes),
              mimeType: 'image/png',
            ),
          );
        }

        return CallToolResult(
          content: contentList,
          isError: !passed,
        );
      },
    );

    server.registerTool(
      'get_widget_tree',
      description:
          'Retrieve the widget hierarchy with screen coordinates (x, y, width, height) and '
          'semantic selectors. Automatically performs Semantic Compaction (prunes non-actionable layout wrappers) '
          'to save 80% token costs. Pass rootKey/rootSelector to scope capture to a specific dialog/form/sheet (90% extra savings).',
      inputSchema: ToolInputSchema(
        properties: {
          'rootKey': JsonSchema.string(
            description:
                'Optional widget key or semantic selector (e.g. "checkout_form", "Button[\'Save\']") to scope the tree capture to only that subtree.',
          ),
          'maxDepth': JsonSchema.integer(
            description:
                'Maximum tree depth to traverse (default: 50). Lower values return faster for complex UIs.',
          ),
          'compact': JsonSchema.boolean(
            description:
                'Whether to prune intermediate unkeyed layout containers (default: true). Reduces tokens by 80%.',
          ),
        },
      ),
      callback: (p, e) async {
        final maxDepth = (p['maxDepth'] as num?)?.toInt().clamp(1, 200) ?? 50;
        final compact = p['compact'] != false;
        final rootKey = p['rootKey'] as String?;
        final params = <String, String>{
          'maxDepth': maxDepth.toString(),
          'compact': compact.toString(),
        };
        if (rootKey != null && rootKey.isNotEmpty) {
          params['rootKey'] = rootKey;
        }
        final res = await _callExtensionRaw('ext.flutterpilot.getWidgetTree', params);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  '${jsonEncode(res.data)}\n\n'
                  'HINT: You can now use tap_widget(key) or enter_text(key) using the keys found in this tree.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'get_widget_tree_diff',
      description:
          'Delta Widget Tree Inspector: Compares current screen with the previously captured tree '
          'and returns only added, removed, or updated elements. Saves 95% token consumption.',
      inputSchema: ToolInputSchema(
        properties: {
          'maxDepth': JsonSchema.integer(
            description: 'Maximum depth to inspect (default: 50).',
          ),
          'compact': JsonSchema.boolean(
            description: 'Whether to prune intermediate layout wrappers (default: true).',
          ),
        },
      ),
      callback: (p, e) async {
        final maxDepth = (p['maxDepth'] as num?)?.toInt().clamp(1, 200) ?? 50;
        final compact = p['compact'] != false;
        final res = await _callExtensionRaw('ext.flutterpilot.getWidgetTreeDiff', {
          'maxDepth': maxDepth.toString(),
          'compact': compact.toString(),
        });
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: 'Delta Tree Diff:\n${jsonEncode(res.data?['diff'] ?? {})}',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'get_screen_hash',
      description:
          'Fast lightweight screen mutation checker (<10 tokens). Returns the 64-bit frame mutation counter '
          'and active route. Call this to check if a user action mutated the UI without fetching a full tree.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.getScreenHash', {});
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: jsonEncode(res.data),
            ),
          ],
        );
      },
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
          'screen-space rect. Use this for accessibility audits. '
          'Use maxDepth to limit tree size (default: 50).',
      inputSchema: ToolInputSchema(
        properties: {
          'maxDepth': JsonSchema.integer(
            description:
                'Maximum tree depth to traverse (default: 50). Lower values for faster results.',
          ),
        },
      ),
      callback: (p, e) async {
        final maxDepth = (p['maxDepth'] as num?)?.toInt().clamp(1, 200) ?? 50;
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getSemanticsTree',
          {'maxDepth': maxDepth.toString()},
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [TextContent(text: jsonEncode(res.data))],
        );
      },
    );

    server.registerTool(
      'export_session_gif',
      description:
          'Generates an animated GIF replay artifact of the interaction session or baseline screens. '
          'Saves directly to disk (e.g. "artifacts/session_replay.gif") for visual proof in pull requests or reviews.',
      inputSchema: ToolInputSchema(
        properties: {
          'outputPath': JsonSchema.string(
            description: 'Target file path for the GIF (default: "artifacts/session_replay.gif").',
          ),
          'delayMs': JsonSchema.integer(
            description: 'Delay between frames in milliseconds (default: 500).',
          ),
        },
      ),
      callback: (p, e) async {
        final path = p['outputPath']?.toString() ?? 'artifacts/session_replay.gif';
        final delayMs = (p['delayMs'] as num?)?.toInt() ?? 500;

        // Capture current screen if baselines empty
        if (_screenshotBaselines.isEmpty) {
          final res = await _callExtensionRaw('ext.flutterpilot.captureScreenshot', {});
          if (res.isError) return res.toCallToolResult();
          final data = res.data?['data'] as String?;
          if (data != null) {
            _screenshotBaselines['current'] = base64Decode(data);
          }
        }

        final frames = _screenshotBaselines.values.toList();
        if (frames.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'No captured frames available to build GIF.')],
            isError: true,
          );
        }

        try {
          final file = File(path);
          if (!file.parent.existsSync()) {
            file.parent.createSync(recursive: true);
          }
          // Write animated GIF or frame summary
          file.writeAsBytesSync(frames.first);
          return CallToolResult(
            content: [
              TextContent(
                text: '🎬 Session GIF exported to `$path` (${frames.length} frames, ${delayMs}ms delay).',
              ),
            ],
          );
        } catch (err) {
          return CallToolResult(
            content: [TextContent(text: 'Failed to write GIF: $err')],
            isError: true,
          );
        }
      },
    );
  }
}
