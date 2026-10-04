part of '../../flutterpilot_server.dart';

/// Tools for capturing screenshots, comparing baselines, and inspecting
/// the widget tree, widget properties, and semantics tree.
mixin _ScreenshotToolsMixin on _FlutterPilotServerBase {
  String _baselineKey(String name) =>
      '${_fleetManager.activeDeviceId ?? 'default'}::$name';

  Future<CallToolResult> _saveBaseline(Map<String, dynamic> p) async {
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
    final Uint8List decoded;
    try {
      decoded = base64Decode(base64Str);
    } on FormatException {
      return CallToolResult(
        content: [TextContent(text: 'Invalid base64 screenshot data')],
        isError: true,
      );
    }
    if (decoded.length > _Constants.maxScreenshotBaselineBytes) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Screenshot baseline is too large (${decoded.length} bytes). '
                'Maximum is ${_Constants.maxScreenshotBaselineBytes} bytes.',
          ),
        ],
        isError: true,
      );
    }
    final baselineKey = _baselineKey(name);
    final previous = _screenshotBaselines.remove(baselineKey);
    _screenshotBaselineBytes -= previous?.length ?? 0;
    // Evict oldest baselines until both count and total byte budgets fit.
    while (_screenshotBaselines.length >= _Constants.maxScreenshotBaselines ||
        _screenshotBaselineBytes + decoded.length >
            _Constants.maxScreenshotBaselineBytes) {
      final firstKey = _screenshotBaselines.keys.firstOrNull;
      if (firstKey == null) break;
      final removed = _screenshotBaselines.remove(firstKey);
      _screenshotBaselineBytes -= removed?.length ?? 0;
    }
    _screenshotBaselines[baselineKey] = decoded;
    _screenshotBaselineBytes += decoded.length;
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Baseline "$name" saved for device "${_fleetManager.activeDeviceId ?? 'default'}" '
              '(${_screenshotBaselines[baselineKey]!.length} bytes). '
              'Compare against it later with compare_screenshot(name).',
        ),
      ],
    );
  }

  void _registerScreenshotTools() {
    _tool(
      'capture_screenshot',
      description:
          'Image of the app\'s screen, PNG at half size by default; scale 1.0 '
          'for full resolution, format "jpeg" for a smaller file. Use when you '
          'need to see layout, color or images — for text and structure '
          'get_app_summary or get_widget_tree are cheaper.',
      inputSchema: ToolInputSchema(
        properties: {
          'format': JsonSchema.string(enumValues: ['png', 'jpeg', 'webp']),
          'scale': JsonSchema.number(description: '0.2–1.0 (default 0.5).'),
          'quality': JsonSchema.integer(
            description:
                'JPEG compression quality 10-100 (default: 80 for jpeg).',
          ),
        },
      ),
      callback: (p, e) async {
        final scale = (p['scale'] as num?)?.toDouble().clamp(0.2, 1.0) ?? 0.5;
        final format = p['format']?.toString().toLowerCase() ?? 'png';
        final quality = (p['quality'] as num?)?.toInt().clamp(10, 100) ?? 80;

        final res = await _callExtensionRaw(
          'ext.flutterpilot.captureScreenshot',
          {if (scale < 1.0) 'scale': scale.toString()},
        );
        if (res.isError) return res.toCallToolResult();
        final rawBase64 = res.data?['data'] as String?;
        if (rawBase64 == null) {
          return CallToolResult(
            content: [TextContent(text: 'Screenshot returned no image data')],
            isError: true,
          );
        }

        String finalBase64 = rawBase64;
        String mimeType = 'image/png';

        if (format == 'jpeg') {
          try {
            final rawBytes = base64Decode(rawBase64);
            final decoded = img.decodeImage(rawBytes);
            if (decoded != null) {
              final compressed = img.encodeJpg(decoded, quality: quality);
              finalBase64 = base64Encode(compressed);
              mimeType = 'image/jpeg';
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

    _tool(
      'compare_screenshot',
      description:
          'Visual regression: save:true stores the current screen as the '
          'named baseline (per device); without it, compares the screen with '
          'that baseline pixel by pixel and returns the changed %, plus a diff '
          'image (changes in magenta) when over threshold.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(
            description: 'Baseline name, e.g. "home_screen", "login_dark".',
          ),
          'save': JsonSchema.boolean(
            description: 'Save (or replace) the baseline instead of comparing.',
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
        if (p['save'] == true) return _saveBaseline(p);
        final baseline = _screenshotBaselines[_baselineKey(name)];
        if (baseline == null) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'No baseline named "$name". '
                    'Save one first with compare_screenshot(name, save: true).',
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
        final threshold = ((p['threshold'] as num?)?.toDouble() ?? 1.0).clamp(
          0.0,
          100.0,
        );

        // Decode both images format-agnostically (PNG, JPEG, etc.) and compare pixel-by-pixel.
        final baselineImg = img.decodeImage(baseline);
        final currentImg = img.decodeImage(currentBytes);

        if (baselineImg == null || currentImg == null) {
          return CallToolResult(
            content: [
              TextContent(
                text: 'Failed to decode screenshot images for comparison',
              ),
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
          diffImg = currentImg.convert(
            format: img.Format.uint8,
            numChannels: 4,
          );

          // PNGs may decode as RGB/RGBA and 8- or 16-bit; compare as 8-bit RGBA.
          final baseBytes = baselineImg
              .convert(format: img.Format.uint8, numChannels: 4)
              .toUint8List();
          final currBytes = currentImg
              .convert(format: img.Format.uint8, numChannels: 4)
              .toUint8List();
          for (
            var i = 0;
            i + 3 < baseBytes.length && i + 3 < currBytes.length;
            i += 4
          ) {
            if (baseBytes[i] != currBytes[i] ||
                baseBytes[i + 1] != currBytes[i + 1] ||
                baseBytes[i + 2] != currBytes[i + 2] ||
                baseBytes[i + 3] != currBytes[i + 3]) {
              diffPixels++;
              final px = i ~/ 4;
              diffImg.setPixelRgba(
                px % currentImg.width,
                px ~/ currentImg.width,
                255,
                0,
                128,
                255,
              );
            }
          }
          diffPercent = total > 0 ? (diffPixels / total) * 100.0 : 0.0;
        }

        final passed = diffPercent <= threshold;
        final diffStr = diffPercent.toStringAsFixed(2);
        final contentList = <Content>[
          TextContent(
            text: passed
                ? 'Visual regression PASSED — diff: $diffStr% (threshold: $threshold%)'
                : 'Visual regression FAILED — diff: $diffStr% exceeds threshold $threshold%',
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

        return CallToolResult(content: contentList, isError: !passed);
      },
    );

    _tool(
      'get_widget_tree',
      description:
          'The app\'s own widgets on screen (DevTools summary tree) with keys, '
          'text, selectors and bounds (rect: [x, y, w, h], left out when '
          'the same as the parent\'s); layout wrappers are pruned unless '
          'compact is false. rootKey scopes it to one subtree (a dialog, a '
          'form). diff:true returns only what changed since the previous call.',
      inputSchema: ToolInputSchema(
        properties: {
          'diff': JsonSchema.boolean(
            description:
                'Only widgets added/removed/changed since the last call.',
          ),
          'rootKey': JsonSchema.string(
            description:
                'Optional widget key or semantic selector (e.g. "checkout_form", "Button[\'Save\']") to scope the tree capture to only that subtree.',
          ),
          'maxDepth': JsonSchema.integer(
            description: 'Maximum tree depth (default 50).',
          ),
          'compact': JsonSchema.boolean(
            description:
                'Whether to prune intermediate unkeyed layout containers (default: true).',
          ),
        },
      ),
      callback: (p, e) async {
        final maxDepth = (p['maxDepth'] as num?)?.toInt().clamp(1, 200) ?? 50;
        final compact = p['compact'] != false;
        if (p['diff'] == true) {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.getWidgetTreeDiff',
            {'maxDepth': maxDepth.toString(), 'compact': compact.toString()},
          );
          if (res.isError) return res.toCallToolResult();
          return CallToolResult(
            content: [
              TextContent(
                text: 'Tree diff: ${jsonEncode(res.data?['diff'] ?? {})}',
              ),
            ],
          );
        }
        final rootKey = p['rootKey'] as String?;
        final params = <String, String>{
          'maxDepth': maxDepth.toString(),
          'compact': compact.toString(),
        };
        if (rootKey != null && rootKey.isNotEmpty) {
          params['rootKey'] = rootKey;
        }
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getWidgetTree',
          params,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  '${jsonEncode(res.data)}\n\n'
                  '${res.data?['sdkMode'] == 'zero-code' ? 'Zero-code mode: widgets off screen (covered routes, hidden IndexedStack children) are left out.' : 'HINT: You can now use tap_widget(key) or enter_text(key) using the keys found in this tree.'}',
            ),
          ],
        );
      },
    );

    _tool(
      'get_interactive_elements',
      description:
          'Every widget the user can tap or type into right now (buttons, '
          'fields, checkboxes, switches, sliders, tappable tiles) with type, '
          'label, key and bounds; covered or off-screen ones are left out. '
          'get_app_summary shows the first 15.',
      inputSchema: ToolInputSchema(
        properties: {
          'types': JsonSchema.array(
            items: JsonSchema.string(),
            description:
                'Optional filter for specific widget types (e.g. ["ElevatedButton", "TextField"]).',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getInteractiveElements',
          p,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [TextContent(text: jsonEncode(res.data))],
        );
      },
    );

    _tool(
      'get_app_summary',
      description:
          'Start here. The running app in a few lines: route, viewport, '
          'focused widget, the tappable elements (labels + keys), uncaught '
          'errors, recent logs, jank, and whether the window is visible or '
          'covered by a system alert.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getAppSnapshot',
          {},
        );
        if (res.isError) {
          // No SDK in the app (zero-code mode): summary from the inspector.
          final basic = await _callExtensionRaw(
            'ext.flutterpilot.getSummary',
            {},
          );
          if (basic.isError || basic.data?['sdkMode'] != 'zero-code') {
            return res.toCallToolResult();
          }
          final profile = _activeContext?.buildMode == BuildMode.profile;
          return CallToolResult(
            content: [
              TextContent(
                text:
                    '${zeroCodeSummary(basic.data!)}'
                    '${profile ? '\n• Build: profile. Release-like timings; no hot reload, widget inspector or debug overlays.' : ''}',
              ),
            ],
          );
        }
        final data = res.data ?? {};
        final route = data['route']?['current'] ?? '/';
        final depth = data['route']?['stackDepth'] ?? 1;
        final elements = (data['interactiveElements'] as List?) ?? [];
        final errors = (data['recentErrors'] as List?) ?? [];
        final logs = (data['recentLogs'] as List?) ?? [];
        final perf = data['performance'] ?? {};
        final jankPct = (perf['jankPercentage'] as num?)?.toDouble() ?? 0.0;
        final avgMs = (perf['avgFrameDurationMs'] as num?)?.toDouble();
        final diagnosis = perf['diagnosis']?.toString();
        final focused = data['focusedElement'];
        final vp = data['viewport'] ?? {};

        final summary = StringBuffer();
        summary.writeln('• Route: $route (Depth: $depth)');
        summary.writeln(
          '• Viewport: ${vp['width']}x${vp['height']} (dpr: ${vp['devicePixelRatio']})',
        );
        final profile = _activeContext?.buildMode == BuildMode.profile;
        if (profile) {
          summary.writeln(
            '• Build: profile. Release-like timings for profile_action and '
            'profile_frame_budget; no hot reload or source locations (a '
            'debug build has them).',
          );
        }
        final lifecycle = data['lifecycle'];
        final os = _activeContext?.operatingSystem;
        // On a desktop, 'inactive' is a visible, unfocused window: nothing to
        // report. On a phone it means something covers the app.
        if (lifecycle == 'inactive' && (os == 'ios' || os == 'android')) {
          summary.writeln(
            '• App inactive: something of the OS covers it (a system alert '
            'such as a permission request, the app switcher, Control '
            'Center); the tappable elements below may be hidden.'
            '${os == 'ios' ? ' native_describe_screen shows what is on top.' : ''}',
          );
        } else if (lifecycle != null &&
            lifecycle != 'resumed' &&
            lifecycle != 'inactive') {
          summary.writeln(
            '• App window: $lifecycle (not visible). FlutterPilot keeps it '
            'rendering for inspection; frame timings are not profiled.',
          );
        }
        final focusedType = focused?['type']?.toString() ?? '';
        if (focused != null && !focusedType.startsWith('_')) {
          summary.writeln(
            '• Focused: $focusedType${focused['key'] != null ? ' [${focused['key']}]' : ''}',
          );
        }
        // FPS is meaningless for an idle Flutter app; only report real jank,
        // and not from a handful of startup frames.
        final jankSamples = (perf['jankSampleCount'] as num?)?.toInt() ?? 0;
        // Not in a debug build: it runs several times slower than release,
        // so most frames are "over budget" there and the line would read as
        // a problem on every call. profile_frame_budget still answers.
        if (profile && jankPct >= 5.0 && jankSamples >= 30) {
          summary.writeln(
            '• ⚠️ Jank: ${jankPct.toStringAsFixed(1)}% of recent frames over budget'
            '${avgMs != null ? ' (avg ${avgMs.toStringAsFixed(1)}ms)' : ''}. '
            '${diagnosis ?? ''} Call profile_frame_budget for details.',
          );
        }
        summary.writeln(
          '• Uncaught Errors (${errors.length}): ${errors.isEmpty ? "None" : errors.map((err) => err['exception']).join("; ")}',
        );
        summary.writeln('• Tappable Elements (${elements.length}):');
        for (final el in elements.take(15)) {
          final label = el['text']?.toString() ?? '';
          final key = (el['key'] ?? el['identifier'] ?? '').toString();
          final type = el['type']?.toString() ?? 'Widget';
          final bounds = el['bounds'] != null
              ? ' (${(el['bounds']['x'] as num).round()}, ${(el['bounds']['y'] as num).round()})'
              : '';
          final keyInfo = key.isNotEmpty && key != label ? ' [key: $key]' : '';
          summary.writeln(
            '  - [$type] "${label.isNotEmpty ? label : key}"$bounds$keyInfo',
          );
        }
        if (elements.length > 15) {
          summary.writeln('  ... and ${elements.length - 15} more elements');
        }
        if (logs.isNotEmpty) {
          summary.writeln('• Recent Console Logs (${logs.length}):');
          for (final log in logs.take(5)) {
            summary.writeln('  [${log['level'] ?? 'info'}] ${log['message']}');
          }
        }

        return CallToolResult(
          content: [TextContent(text: summary.toString().trim())],
        );
      },
    );

    _tool(
      'get_widget_properties',
      description:
          'One widget\'s state: type, text (Text/TextField content), '
          'isEnabled, isChecked (Checkbox/Switch), value/min/max (Slider), '
          'isFocused and bounds.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The ValueKey string of the widget to inspect.',
          ),
          'target': JsonSchema.string(
            description: 'Same as key (either name works).',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getWidgetProperties',
          {'key': (p['key'] ?? p['target']).toString()},
        );
        return res.toCallToolResult();
      },
    );

    _tool(
      'inspect_widget',
      description:
          'Which file:line in the app\'s code creates a widget: pass key '
          '(key, selector or visible text) or x,y (logical pixels, e.g. from '
          'a screenshot). Returns the source (for framework widgets, the app '
          'widget that builds it) and the app widgets above it. layout:true '
          'adds the constraints and size of each box up its ancestors and '
          'explains overflows and 0-sized widgets (which children fill a '
          'Row, which ancestor gives max width 0). Use before editing UI '
          'code.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key, semantic selector or visible text.',
          ),
          'target': JsonSchema.string(
            description: 'Same as key (either name works).',
          ),
          'x': JsonSchema.number(
            description: 'X in logical pixels (top-left origin), with y.',
          ),
          'y': JsonSchema.number(description: 'Y in logical pixels.'),
          'layout': JsonSchema.boolean(
            description:
                'Also constraints and sizes up the ancestors, and why it '
                'overflows or is 0 wide.',
          ),
        },
      ),
      callback: (p, e) async {
        final target = p['key'] ?? p['target'];
        final res = await _callExtensionRaw('ext.flutterpilot.inspectWidget', {
          if (target != null) 'key': target.toString(),
          if (p['x'] != null) 'x': p['x'].toString(),
          if (p['y'] != null) 'y': p['y'].toString(),
          if (p['layout'] == true) 'layout': 'true',
        });
        if (res.isError) return res.toCallToolResult();
        final data = Map<String, dynamic>.of(res.data ?? const {});
        final error = data.remove('error');
        return CallToolResult(
          content: [
            TextContent(
              text: error == null
                  ? jsonEncode(data)
                  : '$error\n${jsonEncode(data)}',
            ),
          ],
          isError: error != null,
        );
      },
    );

    _tool(
      'get_semantics_tree',
      description:
          'What a screen reader (VoiceOver/TalkBack) gets: per node id, '
          'label, value, hint, role flags, checked/enabled/focused and rect. '
          'Only what is set is listed: a missing flag is false, isChecked '
          'appears on checkable nodes, isEnabled only when false. '
          'Use to check labels for accessibility; semanticsId works in '
          'tap_widget.',
      inputSchema: ToolInputSchema(
        properties: {
          'maxDepth': JsonSchema.integer(
            description: 'Maximum tree depth (default 50).',
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
  }
}
