part of '../../flutterpilot_server.dart';

/// Tools for navigating routes and changing theme, locale, text scale,
/// orientation and the framework's debug overlays.
mixin _NavigationToolsMixin on _FlutterPilotServerBase {
  void _registerNavigationTools() {
    _tool(
      'navigate_to',
      description:
          'Goes to a route directly, e.g. "/profile/123" (go_router: '
          'router.go; otherwise Navigator.pushNamed). action "push"/"replace" '
          'use go_router\'s push/replace. deepLink:true opens the URL the way '
          'an OS deep link does (e.g. "myapp://product/123"). Back: '
          'press_key("back").',
      inputSchema: ToolInputSchema(
        properties: {
          'route': JsonSchema.string(
            description:
                'Route or deep-link URL (e.g. "/home", "/profile/123").',
          ),
          'action': JsonSchema.string(
            enumValues: ['go', 'push', 'replace'],
            description:
                'Default "go". push/replace need the go_router plugin.',
          ),
          'deepLink': JsonSchema.boolean(
            description: 'Open route as an OS deep link.',
          ),
        },
        required: ['route'],
      ),
      callback: (p, e) async {
        final route = p['route'].toString();
        final action = p['action']?.toString() ?? 'go';
        final _ExtensionResult res;
        if (p['deepLink'] == true) {
          res = await _callExtensionRaw('ext.flutterpilot.simulateDeepLink', {
            'url': route,
          });
        } else if (action == 'push' || action == 'replace') {
          res = await _callExtensionRaw('ext.flutterpilot.goRouterNavigate', {
            'location': route,
            'action': action,
          });
        } else {
          res = await _callExtensionRaw('ext.flutterpilot.navigateTo', {
            'route': route,
          });
        }
        if (res.isError) return res.toCallToolResult();
        final stack = await _callExtensionRaw(
          'ext.flutterpilot.getNavigationStack',
          {},
        );
        final now = (stack.data?['stack'] as List?)?.join(' -> ');
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Navigated to "$route"${now != null ? '. Stack: $now' : ''}.',
            ),
          ],
        );
      },
    );

    _tool(
      'get_navigation_stack',
      description:
          'The route stack, bottom to top. With go_router also the location, '
          'path/query parameters and matched routes; routes:true adds the '
          'router\'s route table, history:true the recent route changes.',
      inputSchema: ToolInputSchema(
        properties: {
          'routes': JsonSchema.boolean(
            description: 'Include go_router\'s configured routes.',
          ),
          'history': JsonSchema.boolean(
            description: 'Include recent route changes (go_router).',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getNavigationStack',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final buf = StringBuffer(
          'Navigation stack: ${(res.data?['stack'] as List?)?.join(' -> ') ?? 'empty'}',
        );
        final router = await _callExtensionRaw(
          'ext.flutterpilot.getGoRouterState',
          {},
        );
        if (!router.isError) {
          final json = router.data!;
          buf.write('\ngo_router location: ${json['currentLocation']}');
          final pathParams = json['pathParameters'] as Map? ?? {};
          if (pathParams.isNotEmpty) buf.write('\nPath params: $pathParams');
          final queryParams = json['queryParameters'] as Map? ?? {};
          if (queryParams.isNotEmpty) buf.write('\nQuery params: $queryParams');
          buf.write('\nCan pop: ${json['canPop']}');
          for (final m in json['matchedRoutes'] as List? ?? const []) {
            buf.write('\n  Matched: ${m['matchedLocation']} → ${m['route']}');
          }
          for (final (flag, ext, label) in [
            ('routes', 'ext.flutterpilot.getGoRouterConfig', 'Routes'),
            ('history', 'ext.flutterpilot.getGoRouterHistory', 'History'),
          ]) {
            if (p[flag] != true) continue;
            final extra = await _callExtensionRaw(ext, {});
            buf.write(
              '\n$label: ${extra.isError ? extra.errorMessage : jsonEncode(extra.data)}',
            );
          }
        } else if (p['routes'] == true || p['history'] == true) {
          buf.write(
            '\n(routes and history need the go_router plugin; this app has '
            'not registered it.)',
          );
        }
        return CallToolResult(
          content: [
            TextContent(
              text: FlutterPilotServer._boundToolText(buf.toString()),
            ),
          ],
        );
      },
    );

    _tool(
      'set_app_settings',
      description:
          'Changes how the app renders, one or more at once: theme '
          '(light/dark), locale ("fr", "ar", "system"), textScale (2.0 to '
          'test large text; 0 resets), orientation (portrait/landscape/all, '
          'phones), windowSize ("390x844", macOS desktop window), and the '
          'debug overlays debugPaint (layout bounds), repaintRainbow (what '
          'repaints) and slowAnimations (5x slower). Locale and textScale '
          'act like the device setting, with no app code: the response says '
          'what the app shows, e.g. when it does not support the locale or '
          'clamps text scaling. Pair with audit_screen_health to catch '
          'overflows.',
      inputSchema: ToolInputSchema(
        properties: {
          'theme': JsonSchema.string(enumValues: ['light', 'dark']),
          'locale': JsonSchema.string(
            description:
                'BCP-47 tag (e.g. "en", "en-GB", "zh-Hans-CN"); "system" '
                'restores the device locale.',
          ),
          'textScale': JsonSchema.number(
            description:
                'Text scale factor (1.0 normal); 0 restores the system value.',
          ),
          'orientation': JsonSchema.string(
            enumValues: ['portrait', 'landscape', 'all'],
          ),
          'windowSize': JsonSchema.string(
            description:
                'macOS desktop: the window\'s size in logical pixels, '
                '"WIDTHxHEIGHT" (e.g. "390x844" for a phone width, '
                '"1280x860"). The title bar is part of the height.',
          ),
          'debugPaint': JsonSchema.boolean(),
          'repaintRainbow': JsonSchema.boolean(),
          'slowAnimations': JsonSchema.boolean(),
        },
      ),
      callback: (p, e) async {
        final steps = <(String, String, Map<String, dynamic>)>[
          if (p['theme'] != null)
            (
              'theme ${p['theme']}',
              'ext.flutter.brightnessOverride',
              {
                'value': p['theme'] == 'dark'
                    ? 'Brightness.dark'
                    : 'Brightness.light',
              },
            ),
          if (p['locale'] != null)
            (
              'locale ${p['locale']}',
              'ext.flutterpilot.setLocale',
              {'locale': p['locale'].toString()},
            ),
          if (p['textScale'] != null)
            (
              'text scale ${p['textScale']}',
              'ext.flutterpilot.setTextScaleFactor',
              {'scale': p['textScale'].toString()},
            ),
          if (p['orientation'] != null)
            (
              'orientation ${p['orientation']}',
              'ext.flutterpilot.setOrientation',
              {'orientation': p['orientation'].toString()},
            ),
          if (p['debugPaint'] != null)
            (
              'debug paint ${p['debugPaint'] == true ? 'on' : 'off'}',
              'ext.flutter.debugPaint',
              {'enabled': (p['debugPaint'] == true).toString()},
            ),
          if (p['repaintRainbow'] != null)
            (
              'repaint rainbow ${p['repaintRainbow'] == true ? 'on' : 'off'}',
              'ext.flutter.repaintRainbow',
              {'enabled': (p['repaintRainbow'] == true).toString()},
            ),
          if (p['slowAnimations'] != null)
            (
              'slow animations ${p['slowAnimations'] == true ? 'on' : 'off'}',
              'ext.flutter.timeDilation',
              {'timeDilation': p['slowAnimations'] == true ? '5.0' : '1.0'},
            ),
        ];
        if (steps.isEmpty && p['windowSize'] == null) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'Nothing to change: pass theme, locale, textScale, '
                    'orientation, windowSize, debugPaint, repaintRainbow or '
                    'slowAnimations.',
              ),
            ],
          );
        }
        final lines = <String>[];
        var failed = false;
        if (p['windowSize'] != null) {
          final outcome = await _setWindowSize(p, '${p['windowSize']}');
          failed = failed || outcome.failed;
          lines.add(outcome.line);
        }
        for (final (label, ext, args) in steps) {
          final res = await _callExtensionRaw(ext, args);
          if (res.isError) {
            failed = true;
            lines.add('✗ $label: ${res.errorMessage}');
          } else {
            final note = res.data?['note'];
            lines.add(switch (res.data?['status']) {
              'skipped' => '– $label skipped: $note',
              // Applied to the device settings, but the app ignores or
              // clamps it: a finding about the app, not a tool failure.
              'no_effect' => '– $label had no effect: $note',
              'limited' => '– $label partly applied: $note',
              _ => '✓ $label${note != null ? ' ($note)' : ''}',
            });
          }
        }
        return CallToolResult(
          isError: failed,
          content: [TextContent(text: lines.join('\n'))],
        );
      },
    );
  }

  /// set_app_settings(windowSize): resizes the window on the host, then
  /// reports the viewport the app now has.
  Future<({String line, bool failed})> _setWindowSize(
    Map<String, dynamic> p,
    String value,
  ) async {
    final size = parseWindowSize(value);
    if (size == null) {
      return (
        line: '✗ window size "$value": use WIDTHxHEIGHT, e.g. "390x844".',
        failed: true,
      );
    }
    final label = 'window ${size.width}x${size.height}';
    final context = await _deviceContextForParameters(p);
    final vm = context?.service;
    final pid = vm == null ? null : (await vm.getVM()).pid;
    Future<String?> viewport() async {
      final snapshot = await _callExtensionRaw(
        'ext.flutterpilot.getAppSnapshot',
        {},
      );
      final v = snapshot.data?['viewport'];
      return v is Map ? '${v['width']}x${v['height']}' : null;
    }

    final before = await viewport();
    final problem = await resizeAppWindow(
      // A web app's VM reports the host's OS; the browser owns its window.
      operatingSystem: context?.isWeb ?? false
          ? 'web'
          : context?.operatingSystem,
      pid: pid,
      width: size.width,
      height: size.height,
    );
    if (problem != null) return (line: '✗ $label: $problem', failed: true);
    // The app lays out again a frame or two after the window changes.
    var after = before;
    // Up to 8 s: a covered or busy app takes its time to draw the new size.
    for (var i = 0; i < 40 && after == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      after = await viewport();
    }
    if (after == null) return (line: '✓ $label', failed: false);
    if (after == before && !after.startsWith('${size.width}x')) {
      // Told to resize and nothing moved: a window with a fixed or minimum
      // size, or one that is full screen.
      return (
        line:
            '✗ $label: the window was asked to resize but the viewport is '
            'still $after (a fixed, minimum or full-screen window).',
        failed: true,
      );
    }
    return (line: '✓ $label (viewport now $after)', failed: false);
  }
}
