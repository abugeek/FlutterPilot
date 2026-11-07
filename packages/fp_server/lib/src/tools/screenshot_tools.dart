part of '../../fp_server.dart';

/// Tools for capturing screenshots, comparing baselines, and inspecting
/// the widget tree, widget properties, and semantics tree.
mixin _ScreenshotToolsMixin on _FlutterPilotServerBase {
  static Uint8List? _lastScreenshotBytes;

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
      _lastScreenshotBytes = decoded;
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

  /// get_app_summary: from the SDK's snapshot, or without the SDK from the
  /// inspector.
  Future<CallToolResult> _appSummary() async {
    final res = await _callExtensionRaw('ext.flutterpilot.getAppSnapshot', {});
    if (res.isError) {
      // No SDK in the app (zero-code mode): summary from the inspector.
      final basic = await _callExtensionRaw('ext.flutterpilot.getSummary', {});
      if (basic.isError || basic.data?['sdkMode'] != 'zero-code') {
        return withVerdict(
          res.toCallToolResult(),
          appSummaryVerdict(connected: false),
        );
      }
      final profile = _activeContext?.buildMode == BuildMode.profile;
      final stale = await _staleCodeNote();
      final deviceState = await _phoneState();
      final device = deviceState?.problem;
      // Zero-code keeps its own error records; split them the same way.
      final zeroCodeErrors = errorsByReload(
        ((basic.data?['errors'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        _activeContext?.lastReload,
      );
      return withVerdict(
        CallToolResult(
          content: [
            TextContent(
              text:
                  '${stale == null ? '' : '• Code: $stale\n'}'
                  '${device == null ? '' : '• Device: $device. ${deviceState!.fix}\n'}'
                  '${zeroCodeSummary(basic.data!, lastReload: _activeContext?.lastReload)}'
                  '${profile ? '\n• Build: profile. Release-like timings; no hot reload, widget inspector or debug overlays.' : ''}',
            ),
          ],
        ),
        appSummaryVerdict(
          connected: true,
          device: _fleetManager.activeDeviceId,
          platform: _activeContext?.operatingSystem,
          errorCount: zeroCodeErrors.since.length,
          buildMode: _activeContext?.buildMode?.name,
        ),
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
    final protocol = _activeContext?.sdkProtocol;
    if (protocol != null) {
      if (protocolNote(protocol) case final note?) {
        summary.writeln('• Versions: $note');
      }
    }
    if (await _staleCodeNote() case final stale?) {
      summary.writeln('• Code: $stale');
    }
    if (await _phoneState() case final state? when state.problem != null) {
      summary.writeln('• Device: ${state.problem}. ${state.fix}');
    }
    if (_connectionNote case final note?) {
      _connectionNote = null;
      summary.writeln('• Connection: $note');
    }
    if (data['starting'] case final String why) {
      summary.writeln('• Starting: $why');
    }
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
        '${_allTools['native_describe_screen']?.enabled == true ? ' native_describe_screen shows what is on top.' : ''}',
      );
      if (await _permissionDialogHint() case final hint?) {
        summary.writeln(hint);
      }
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
    // The reload's fix may already have landed: an error from before it is not
    // an uncaught exception of the code now running (field test #334). Same
    // rule as get_errors, marked the same way.
    final errorSplit = errorsByReload(
      errors.whereType<Map<String, dynamic>>().toList(),
      _activeContext?.lastReload,
    );
    summary.writeln(
      '• Uncaught Errors (${errorSplit.since.length}): ${errorSplit.since.isEmpty ? "None" : errorSplit.since.map((err) => err['exception']).join("; ")}',
    );
    if (errorSplit.before.isNotEmpty) {
      summary.writeln(
        '• ${beforeReloadNote(errorSplit.before.length)}: '
        '${errorSplit.before.map((err) => err['exception']).join("; ")}. '
        'get_errors(report: true) has the crash report when one was built.',
      );
    }
    final health = data['health'];
    if (health is Map) {
      final isHealthy = health['isHealthy'] == true;
      final overflows = (health['overflowCount'] as num?)?.toInt() ?? 0;
      final a11y = (health['accessibilityIssueCount'] as num?)?.toInt() ?? 0;
      if (isHealthy) {
        summary.writeln('• Health: ✓ Clean (no overflows or small tap targets)');
      } else {
        final issues = [
          if (overflows > 0) '$overflows layout overflow(s)',
          if (a11y > 0) '$a11y small tap target(s)',
        ];
        summary.writeln(
          '• Health: ⚠️ ${issues.join(', ')} — call audit_screen_health for details',
        );
      }
    }
    summary.writeln('• Tappable Elements (${elements.length}):');
    for (final el in elements.take(15)) {
      final label = el['text']?.toString() ?? '';
      final key = (el['key'] ?? el['identifier'] ?? '').toString();
      final type = el['type']?.toString() ?? 'Widget';
      final bounds = el['bounds'] != null
          ? ' (${(el['bounds']['x'] as num).round()}, ${(el['bounds']['y'] as num).round()})'
          : '';
      final keyInfo = key.isNotEmpty && key != label ? ' [key: $key]' : '';
      final error = el['fieldError'] == null
          ? ''
          : ' ⚠ error: ${el['fieldError']}';
      summary.writeln(
        '  - [$type] "${label.isNotEmpty ? label : key}"$bounds$keyInfo'
        '$error',
      );
    }
    final elementNote = truncationNote(
      shown: elements.length > 15 ? 15 : elements.length,
      total: elements.length,
      what: 'tappable elements (first kept)',
      how: 'get_interactive_elements lists them all.',
    );
    if (elementNote != null) summary.writeln('  $elementNote');
    if (logs.isNotEmpty) {
      summary.writeln('• Recent Console Logs (${logs.length}):');
      for (final log in logs.take(5)) {
        summary.writeln('  [${log['level'] ?? 'info'}] ${log['message']}');
      }
      final logNote = truncationNote(
        shown: logs.length > 5 ? 5 : logs.length,
        total: logs.length,
        what: 'recent console logs (newest kept)',
        how:
            'get_debug_logs(level, query, sinceSeconds, logger, limit) has '
            'the rest.',
      );
      if (logNote != null) summary.writeln('  $logNote');
    }

    return withVerdict(
      CallToolResult(content: [TextContent(text: summary.toString().trim())]),
      appSummaryVerdict(
        connected: true,
        device: _fleetManager.activeDeviceId,
        platform: _activeContext?.operatingSystem,
        route: route.toString(),
        errorCount: errorSplit.since.length,
        buildMode: _activeContext?.buildMode?.name,
      ),
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
          'labeled': JsonSchema.boolean(
            description: 'Overlay numbered badges on interactive elements.',
          ),
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
        final labeled = p['labeled'] == true;

        final res = await _callExtensionRaw(
          'ext.flutterpilot.captureScreenshot',
          {
            if (scale < 1.0) 'scale': scale.toString(),
            if (labeled) 'labeled': 'true',
          },
        );
        if (res.isError) return res.toCallToolResult();
        final rawBase64 = res.data?['data'] as String?;
        if (rawBase64 == null) {
          return CallToolResult(
            content: [TextContent(text: 'Screenshot returned no image data')],
            isError: true,
          );
        }
        try {
          _lastScreenshotBytes = base64Decode(rawBase64);
        } catch (_) {}

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

        final marks = (res.data?['marks'] as List?) ?? const [];
        final marksListStr = marks.map((m) {
          final markId = m['mark'];
          final type = m['type'];
          final key = m['key'];
          final text = m['text'];
          final label = key ?? text ?? type;
          return '[$markId] $type "$label"${key != null ? ' (key: "$key")' : ''}';
        }).join('\n');
        final marksText = marks.isEmpty
            ? ''
            : '\n\nSet-of-Mark (SoM) Elements (${marks.length}):\n$marksListStr\n\nInteract with: tap_widget(mark: <number>) or enter_text(mark: <number>, text: "...")';

        return CallToolResult(
          content: [
            ImageContent(data: finalBase64, mimeType: mimeType),
            TextContent(
              text:
                  'Screenshot captured ($mimeType, scale: ${scale}x).$marksText',
            ),
          ],
        );
      },
    );

    _tool(
      'compare_screenshot',
      description:
          'Visual diff against baseline (or previous frame with '
          'comparePrevious). save:true saves baseline. Returns diff %, '
          'changed bounds, and diff image.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(description: 'Baseline name.'),
          'comparePrevious': JsonSchema.boolean(
            description: 'Compare against previous frame.',
          ),
          'save': JsonSchema.boolean(
            description: 'Save current screen as baseline.',
          ),
          'threshold': JsonSchema.number(
            description: 'Allowed diff % before failing (default 1.0).',
          ),
          'scale': JsonSchema.number(description: '0.2–1.0 (default 0.5).'),
          'ignoreStatusBar': JsonSchema.boolean(
            description: 'Ignore status bar.',
          ),
          'ignoreKeys': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Widget keys to mask out during diffing.',
          ),
        },
      ),
      callback: (p, e) async {
        final comparePrevious = p['comparePrevious'] == true;
        final name = p['name']?.toString();
        if (p['save'] == true) {
          if (name == null || name.isEmpty) {
            return CallToolResult(
              content: [
                TextContent(text: 'name is required to save a baseline'),
              ],
              isError: true,
            );
          }
          return _saveBaseline(p);
        }
        final Uint8List? baseline;
        if (comparePrevious) {
          baseline = _lastScreenshotBytes;
          if (baseline == null) {
            return CallToolResult(
              content: [
                TextContent(
                  text:
                      'No previous screenshot found. Call capture_screenshot or an action first.',
                ),
              ],
              isError: true,
            );
          }
        } else {
          if (name == null || name.isEmpty) {
            return CallToolResult(
              content: [
                TextContent(
                  text: 'name is required unless comparePrevious: true',
                ),
              ],
              isError: true,
            );
          }
          baseline = _screenshotBaselines[_baselineKey(name)];
          if (baseline == null) {
            return CallToolResult(
              content: [
                TextContent(
                  text:
                      'No baseline named "$name". '
                      'Save one first with compare_screenshot(name: "$name", save: true).',
                ),
              ],
              isError: true,
            );
          }
        }

        final scale = (p['scale'] as num?)?.toDouble().clamp(0.2, 1.0) ?? 0.5;
        final res = await _callExtensionRaw(
          'ext.flutterpilot.captureScreenshot',
          {
            if (scale < 1.0) 'scale': scale.toString(),
          },
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
        var baselineImg = img.decodeImage(baseline);
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

        if (baselineImg.width != currentImg.width ||
            baselineImg.height != currentImg.height) {
          baselineImg = img.copyResize(
            baselineImg,
            width: currentImg.width,
            height: currentImg.height,
          );
        }

        double diffPercent = 0.0;
        int diffPixels = 0;
        img.Image? diffImg;
        int minX = currentImg.width;
        int maxX = 0;
        int minY = currentImg.height;
        int maxY = 0;

        final ignoreStatusBar = p['ignoreStatusBar'] == true;
        final statusBarHeight =
            ignoreStatusBar ? (currentImg.height * 0.06).round() : 0;

        final rawKeys = p['ignoreKeys'];
        final ignoreKeys = rawKeys is List
            ? rawKeys.map((k) => k.toString()).toList()
            : const <String>[];
        final maskedBoxes = <({double left, double top, double right, double bottom, String key})>[];
        for (final k in ignoreKeys) {
          final info = await _callExtensionRaw('ext.flutterpilot.inspectWidget', {'key': k});
          final b = info.data?['widget']?['bounds'] as Map?;
          if (b != null) {
            final x = (b['x'] as num).toDouble() * scale;
            final y = (b['y'] as num).toDouble() * scale;
            final w = (b['w'] as num).toDouble() * scale;
            final h = (b['h'] as num).toDouble() * scale;
            maskedBoxes.add((left: x, top: y, right: x + w, bottom: y + h, key: k));
          }
        }

        var total = currentImg.width * (currentImg.height - statusBarHeight);
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
            final py = (i ~/ 4) ~/ currentImg.width;
            if (py < statusBarHeight) continue;
            final px = (i ~/ 4) % currentImg.width;

            // Check if pixel falls inside any masked key bounding box
            var isMasked = false;
            for (final box in maskedBoxes) {
              if (px >= box.left && px <= box.right && py >= box.top && py <= box.bottom) {
                isMasked = true;
                break;
              }
            }
            if (isMasked) continue;

            if (baseBytes[i] != currBytes[i] ||
                baseBytes[i + 1] != currBytes[i + 1] ||
                baseBytes[i + 2] != currBytes[i + 2] ||
                baseBytes[i + 3] != currBytes[i + 3]) {
              diffPixels++;
              if (px < minX) minX = px;
              if (px > maxX) maxX = px;
              if (py < minY) minY = py;
              if (py > maxY) maxY = py;

              diffImg.setPixelRgba(
                px,
                py,
                255,
                0,
                128,
                255,
              );
            }
          }
          diffPercent = total > 0 ? (diffPixels / total) * 100.0 : 0.0;

        _lastScreenshotBytes = currentBytes;

        final passed = diffPercent <= threshold;
        final diffStr = diffPercent.toStringAsFixed(2);
        final maskNote = maskedBoxes.isEmpty
            ? ''
            : ' (masked: ${maskedBoxes.map((b) => b.key).join(", ")})';

        Map<String, dynamic>? changedBounds;
        String? region;
        if (diffPixels > 0 && maxX >= minX && maxY >= minY) {
          final w = maxX - minX + 1;
          final h = maxY - minY + 1;
          final midX = (minX + maxX) ~/ 2;
          final midY = (minY + maxY) ~/ 2;
          final vert = midY < currentImg.height * 0.33
              ? 'top'
              : (midY > currentImg.height * 0.66 ? 'bottom' : 'middle');
          final horiz = midX < currentImg.width * 0.33
              ? 'left'
              : (midX > currentImg.width * 0.66 ? 'right' : 'center');
          region = '$vert-$horiz';
          changedBounds = {'x': minX, 'y': minY, 'width': w, 'height': h};
        }

        final buf = StringBuffer();
        if (passed) {
          buf.write(
            'Visual comparison PASSED — diff: $diffStr% (threshold: $threshold%)$maskNote',
          );
        } else {
          buf.write(
            'Visual comparison FAILED — diff: $diffStr% exceeds threshold $threshold%$maskNote',
          );
        }
        if (changedBounds != null) {
          buf.write(
            '\nChanged region: ${changedBounds['width']}x${changedBounds['height']} '
            'at (${changedBounds['x']}, ${changedBounds['y']}) ($region of screen).',
          );
        }

        final contentList = <Content>[TextContent(text: buf.toString())];

        if (!passed) {
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
          structuredContent: {
            'passed': passed,
            'diffPercent': diffPercent,
            'diffPixels': diffPixels,
            if (ignoreStatusBar) 'ignoreStatusBar': true,
            'changedBounds': ?changedBounds,
            'region': ?region,
          },
        );
      },
    );

    _tool(
      'get_widget_tree',
      description:
          'The app\'s own widgets on screen (the DevTools summary tree) '
          'with keys, text, selectors and bounds (rect: [x, y, w, h], '
          'left out when the same as the parent\'s). diff:true returns '
          'only what changed since the previous call.',
      inputSchema: ToolInputSchema(
        properties: {
          'diff': JsonSchema.boolean(),
          'rootKey': JsonSchema.string(
            description:
                'Key or selector of the subtree to return (a dialog, a form).',
          ),
          'maxDepth': JsonSchema.integer(description: 'Default 50.'),
          'compact': JsonSchema.boolean(
            description:
                'false keeps the unkeyed layout wrappers (default true: '
                'pruned).',
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
          'label, key and bounds, and fieldError for a field showing a '
          'validation error; covered or off-screen ones are left out. '
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
        // The list is never cut short, but it is only the screen: say so, so
        // a long form below the fold does not look short.
        return CallToolResult(
          content: [
            TextContent(
              text: jsonEncode({
                ...?res.data,
                'total': res.data?['count'],
                'truncated': false,
                'scope': 'on screen only',
                'note':
                    'Controls below or beside the viewport (lazy lists, a '
                    'long form) are not listed. scroll_into_view(key) brings '
                    'one on screen; this list is then complete for what shows.',
              }),
            ),
          ],
        );
      },
    );

    _tool(
      'get_app_summary',
      description:
          'Start here. The running app in a few lines: route, viewport, '
          'focus, tappable elements, errors, health, logs, jank, and '
          'window visibility.',
      inputSchema: ToolInputSchema(
        properties: {
          'setup': JsonSchema.boolean(
            description:
                'Also the server and app setup: connection, plugins the app '
                'registered, SDK capabilities, VM, buffer limits. For when a '
                'tool is missing or refused.',
          ),
        },
      ),
      callback: (p, e) async {
        final summary = await _appSummary();
        if (p['setup'] != true) return summary;
        // Also when there is no summary: the setup says why.
        return keepingStructured(
          summary,
          isError: summary.isError,
          content: [
            ...summary.content,
            TextContent(text: 'Setup: ${await _setupReport()}'),
          ],
        );
      },
    );

    _tool(
      'get_widget_properties',
      description:
          'One widget\'s current state in a few fields: type, text, '
          'isEnabled, isChecked, a slider\'s value/min/max, isFocused, '
          'bounds, and for a form field fieldError (the validation error '
          'it shows) or invalid (what its validator says about the '
          'current value, not shown yet). inspect_widget gives its '
          'source, layout and style.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key or selector of the widget.',
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
          'Where a widget is in the app\'s code (file:line; for a '
          'framework widget, the app widget that builds it) and the app '
          'widgets above it. Pass key, or x,y from a screenshot. layout '
          'and style add the numbers a screenshot can\'t give. Use before '
          'editing UI code and to check a design spec; for a widget\'s '
          'current state get_widget_properties is cheaper.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key, selector or visible text.',
          ),
          'x': JsonSchema.number(
            description: 'X in logical pixels (top-left origin), with y.',
          ),
          'y': JsonSchema.number(description: 'Y in logical pixels.'),
          'layout': JsonSchema.boolean(
            description:
                'Also each box\'s constraints and size up the ancestors, and why '
                'it overflows or is 0 wide.',
          ),
          'style': JsonSchema.boolean(
            description:
                'Also text size, weight and color, paddings (left, top, right, '
                'bottom), fills, borders, radii and elevation of the widget and '
                'what it contains.',
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
          if (p['style'] == true) 'style': 'true',
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
          'maxDepth': JsonSchema.integer(description: 'Default 50.'),
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
