part of '../../fp_server.dart';

/// Tools for navigating routes and changing theme, locale, text scale,
/// orientation and the framework's debug overlays.
mixin _NavigationToolsMixin on _FlutterPilotServerBase {
  void _registerNavigationTools() {
    _tool(
      'navigate_to',
      description:
          'Goes to a route directly, e.g. "/profile/123" (go_router: '
          'router.go; otherwise Navigator.pushNamed). Back: '
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
            description: 'Open route as an OS deep link (myapp://product/1).',
          ),
          'waitFor': JsonSchema.string(
            description: 'Key or text to wait for on the new page.',
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
        if (res.isError) {
          // The navigation never reached the app: the compact result says so
          // instead of leaving it to the error text alone (task 07).
          return withVerdict(
            res.toCallToolResult(),
            navigationVerdict(
              requested: route,
              waitRequired: (p['waitFor']?.toString() ?? '').isNotEmpty,
              completed: false,
              uncertain: true,
              status: 'unavailable',
            ),
          );
        }
        // The route changed: subscribers are pushed the new state (task 27).
        _notifyRouteChanged();
        // The page slides in: until it has, its controls are off screen
        // and the next call would list the page underneath. navigateTo and
        // deep links settle in the app before they answer (route
        // transitions and still text); only the router's push/replace do
        // not. Bounded, since a screen with a spinner never stops
        // animating: the second wait cost up to 1.5 s there.
        if (action == 'push' || action == 'replace') {
          await _callExtensionRaw('ext.flutterpilot.waitForAnimation', {
            'timeoutMs': '1500',
          });
        }
        // The stack and the screen after it are independent reads (the
        // screen is read after the wait when there is one).
        final waitFor = p['waitFor']?.toString();
        final stackFuture = _callExtensionRaw(
          'ext.flutterpilot.getNavigationStack',
          {},
        );
        final screenFuture = waitFor == null || waitFor.isEmpty
            ? _screenAfter(route: false)
            : null;
        final stack = await stackFuture;
        final stackList = (stack.data?['stack'] as List?)
            ?.map((e) => '$e')
            .toList();
        final now = stackList?.join(' -> ');
        final current = (stackList != null && stackList.isNotEmpty)
            ? stackList.last
            : null;
        // The page's data may load after the transition: one call instead
        // of navigate_to then wait_for (52 such pairs in field sessions).
        var waited = '';
        var missing = false;
        final waitRequired = waitFor != null && waitFor.isNotEmpty;
        if (waitRequired) {
          final found = await _callExtensionRaw(
            'ext.flutterpilot.waitForCondition',
            {'selector': waitFor, 'timeoutMs': '5000'},
          );
          missing = found.isError;
          waited = missing
              ? ' But "$waitFor" did not appear within 5 s.'
              : ' "$waitFor" is on screen.';
        }
        return CallToolResult(
          isError: missing,
          content: [
            TextContent(
              text:
                  'Navigated to "$route"${now != null ? '. Stack: $now' : ''}.'
                  '$waited${screenFuture == null ? await _screenAfter(route: false) : await screenFuture}',
            ),
          ],
          // The compact twin: what was asked for, where the app now says it
          // is, whether the wait succeeded, and whether the route is
          // confirmed (an unreadable stack leaves it uncertain).
          structuredContent: navigationVerdict(
            requested: route,
            current: current,
            waitRequired: waitRequired,
            waitStatus: waitRequired ? (missing ? 'missing' : 'found') : null,
            completed: !missing,
            uncertain: current == null,
          ),
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
          'Changes how the app renders — theme, locale, text scale, a '
          'simulated keyboard, orientation, window size, the debug overlays — '
          'as the device would (no app code), and says what the app shows '
          'back. Orientation pins: "portrait"/"landscape" outlive the call; '
          '"auto" releases. Pair with audit_screen_health to catch '
          'overflows.',
      inputSchema: ToolInputSchema(
        properties: {
          'theme': JsonSchema.string(enumValues: ['light', 'dark']),
          'locale': JsonSchema.string(
            description: 'BCP-47 tag (e.g. "fr", "ar", "zh") or "system".',
          ),
          'textScale': JsonSchema.number(
            description: 'Scale factor (1.0 default, 0 restores system).',
          ),
          'keyboardInset': JsonSchema.number(
            description: 'Height in logical pixels (e.g. 300; 0 removes).',
          ),
          'orientation': JsonSchema.string(
            enumValues: ['portrait', 'landscape', 'all', 'auto'],
            description: 'Phones.',
          ),
          'windowSize': JsonSchema.string(
            description: '"WIDTHxHEIGHT" in logical pixels (e.g. "390x844").',
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
          if (p['keyboardInset'] != null)
            (
              'keyboard inset ${p['keyboardInset']}',
              'ext.flutterpilot.setKeyboardInset',
              {'inset': p['keyboardInset'].toString()},
            ),
          if (p['orientation'] != null)
            (
              'orientation ${p['orientation']}',
              'ext.flutterpilot.setOrientation',
              {
                'orientation': orientationExtensionArgument(
                  p['orientation'].toString(),
                ),
              },
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
                    'keyboardInset, orientation, windowSize, debugPaint, repaintRainbow or '
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
        final pinNote = p['orientation'] == null
            ? null
            : orientationPinNote(p['orientation'].toString());
        if (pinNote != null) lines.add(pinNote);
        return CallToolResult(
          isError: failed,
          content: [TextContent(text: lines.join('\n'))],
        );
      },
    );

    _tool(
      'simulate_viewport_matrix',
      description:
          'Resizes a macOS/Windows desktop app\'s window to phone 390x844, '
          'tablet 768x1024 and desktop 1280x800, checks the screen for '
          'overflows and cramped lists at each, then restores the window '
          '(macOS). Desktop apps only.',
      inputSchema: ToolInputSchema(
        properties: {
          'restore': JsonSchema.boolean(
            description:
                'Restore initial window size afterwards (default true).',
          ),
        },
      ),
      callback: (p, e) async {
        const matrix = [
          ('Phone', 390, 844),
          ('Tablet', 768, 1024),
          ('Desktop', 1280, 800),
        ];
        // The real window, as set_app_settings(windowSize) resizes it: a
        // MediaQuery override alone leaves the layout constraints as they
        // were, so a Row never overflows under it.
        final context = await _deviceContextForParameters(p);
        final vm = context?.service;
        final pid = vm == null ? null : (await vm.getVM()).pid;
        final initial = pid != null && context?.operatingSystem == 'macos'
            ? await readAppWindowSize(pid)
            : null;

        final results = <Map<String, dynamic>>[];
        var anyFail = false;
        for (final (label, width, height) in matrix) {
          final resized = await _setWindowSize(p, '${width}x$height');
          if (resized.failed) {
            if (initial != null) await _setWindowSize(p, initial);
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      '${resized.line}\nThe viewport matrix resizes the app '
                      'window, so it needs a macOS or Windows desktop app. '
                      'On phones use run_on_devices with a phone and a tablet.',
                ),
              ],
            );
          }
          final audit = await _callExtensionRaw(
            'ext.flutterpilot.auditScreenHealth',
            {},
          );
          final auditData = audit.data ?? const <String, dynamic>{};
          final overflows = (auditData['overflows'] as List?) ?? const [];
          final cramped =
              (auditData['crampedScrollables'] as List?) ?? const [];
          final pass = overflows.isEmpty && cramped.isEmpty;
          if (!pass) anyFail = true;
          results.add({
            'device': label,
            'viewport': '${width}x$height',
            'pass': pass,
            'overflows': overflows
                .map((o) => o['details'] ?? o['type'])
                .toList(),
            'cramped': cramped.map((c) => c['details'] ?? c['type']).toList(),
          });
        }
        if (p['restore'] != false && initial != null) {
          await _setWindowSize(p, initial);
        }
        final buf = StringBuffer('Viewport Matrix Audit Results:\n');
        for (final r in results) {
          final pass = r['pass'] == true;
          buf.writeln(
            '${pass ? "[PASS]" : "[FAIL]"} ${r['device']} (${r['viewport']})',
          );
          if (!pass) {
            for (final o in (r['overflows'] as List)) {
              buf.writeln('  - Overflow: $o');
            }
            for (final c in (r['cramped'] as List)) {
              buf.writeln('  - Cramped: $c');
            }
          }
        }
        buf.writeln(
          '\nMatrix Verdict: ${anyFail ? "FAIL — responsive layout issues detected" : "PASS — all viewports clean"}',
        );

        return CallToolResult(
          content: [TextContent(text: buf.toString().trim())],
          structuredContent: {
            'verdict': anyFail ? 'fail' : 'pass',
            'matrix': results,
          },
        );
      },
    );

    _tool(
      'simulate_keyboard',
      description:
          'Simulates an on-screen keyboard (viewInsets.bottom, e.g. 320dp), '
          'checks the screen for RenderFlex overflows and whether focused '
          'inputs are obscured, then restores the inset (by default).',
      inputSchema: ToolInputSchema(
        properties: {
          'height': JsonSchema.number(
            description:
                'Keyboard height in logical pixels (default: 320; 0 closes).',
          ),
          'restore': JsonSchema.boolean(
            description:
                'Remove the simulated keyboard afterwards (default true).',
          ),
        },
      ),
      callback: (p, e) async {
        final height = (p['height'] as num?)?.toDouble() ?? 320.0;
        final restore = p['restore'] != false;

        final setRes = await _callExtensionRaw(
          'ext.flutterpilot.setKeyboardInset',
          {'inset': height.toString()},
        );
        if (setRes.isError) return setRes.toCallToolResult();

        await Future<void>.delayed(const Duration(milliseconds: 150));

        final audit = await _callExtensionRaw(
          'ext.flutterpilot.auditScreenHealth',
          {},
        );
        final auditData = audit.data ?? const <String, dynamic>{};
        final overflows = (auditData['overflows'] as List?) ?? const [];

        final interactive = await _callExtensionRaw(
          'ext.flutterpilot.getInteractiveElements',
          {},
        );
        final elements = (interactive.data?['elements'] as List?) ?? const [];
        final focusedInput = elements.firstWhere(
          (el) => el is Map && el['isFocused'] == true,
          orElse: () => null,
        );

        var focusedObscured = false;
        if (focusedInput is Map && focusedInput['bounds'] is Map) {
          final bounds = focusedInput['bounds'] as Map;
          final bottomY =
              (bounds['y'] as num? ?? 0) + (bounds['height'] as num? ?? 0);
          final viewHeight =
              (setRes.data?['height'] as num?)?.toDouble() ?? 844.0;
          final availableHeight = viewHeight - height;
          if (bottomY > availableHeight) {
            focusedObscured = true;
          }
        }

        if (restore && height > 0) {
          await _callExtensionRaw(
            'ext.flutterpilot.setKeyboardInset',
            {'inset': '0'},
          );
        }

        final hasOverflow = overflows.isNotEmpty;
        final pass = !hasOverflow && !focusedObscured;

        final buf = StringBuffer(
          'Simulated on-screen keyboard (${height.toInt()}dp)'
          '${restore ? ' (restored)' : ''}:\n',
        );
        if (pass) {
          buf.write('✓ Screen layout is clean with keyboard open. No overflows.');
        } else {
          buf.write('✗ Layout defects detected with keyboard open:');
          if (hasOverflow) {
            buf.write(
              '\n  • RenderFlex bottom overflow (${overflows.length} issue(s)):',
            );
            for (final o in overflows) {
              buf.write('\n    - ${o['details'] ?? o['type']}');
            }
            buf.write(
              '\n  Prescription: Wrap the screen body in SingleChildScrollView or set Scaffold.resizeToAvoidBottomInset: false.',
            );
          }
          if (focusedObscured) {
            final name =
                focusedInput['label'] ?? focusedInput['key'] ?? 'input';
            buf.write(
              '\n  • Focused text field "$name" is obscured behind the keyboard.',
            );
            buf.write(
              '\n  Prescription: Ensure the input is within a Scrollable or call Scrollable.ensureVisible.',
            );
          }
        }

        return CallToolResult(
          isError: !pass,
          content: [TextContent(text: buf.toString())],
          structuredContent: {
            'pass': pass,
            'height': height,
            'overflowCount': overflows.length,
            'overflows': overflows,
            'focusedObscured': focusedObscured,
            'restored': restore,
          },
        );
      },
    );

    _tool(
      'crawl_app',
      description:
          'Finds reachable screens by tapping list rows, cards, tabs and '
          'navigation destinations (never buttons, toggles or rows named like '
          'actions), one row per list; returns the route graph and each '
          'screen\'s overflow/tap-target counts, then goes back.',
      inputSchema: ToolInputSchema(
        properties: {
          'maxScreens': JsonSchema.integer(
            description: 'Stop after this many taps (default 15).',
          ),
          'restore': JsonSchema.boolean(
            description:
                'Go back to the starting route at the end (default '
                'true).',
          ),
        },
      ),
      callback: (p, e) async {
        final maxTaps = (p['maxScreens'] as num?)?.toInt() ?? 15;
        Future<String> route() async =>
            (await _callExtensionRaw(
              'ext.flutterpilot.getNavigationStack',
              {},
            )).data?['current']?.toString() ??
            '/';
        // /story/123 and /story/456 are one screen.
        String pattern(String r) => r.replaceAllMapped(
          RegExp(r'/(\d+|[0-9a-f-]{8,})(?=/|$|\?)'),
          (_) => '/:id',
        );

        final start = await route();
        final health = <String, Map<String, dynamic>>{};
        final edges = <Map<String, String>>[];
        // route pattern → what was tapped there (a list's rows count once)
        final tried = <String, Set<String>>{};
        var taps = 0;
        var current = start;

        while (taps < maxTaps) {
          final screen = await _callExtensionRaw(
            'ext.flutterpilot.crawlScreen',
            {},
          );
          if (screen.isError) return screen.toCallToolResult();
          final data = screen.data ?? const <String, dynamic>{};
          current = data['currentRoute']?.toString() ?? current;
          final here = pattern(current);
          health.putIfAbsent(
            here,
            () => {
              'route': current,
              'overflows': data['overflowCount'] ?? 0,
              'a11y': data['accessibilityIssueCount'] ?? 0,
            },
          );
          final done = tried.putIfAbsent(here, () => {});
          Map? next;
          for (final c
              in (data['navigableCandidates'] as List? ?? const [])
                  .whereType<Map>()) {
            // Rows of one list are one choice; destinations and tabs each
            // their own.
            final id = const {'ListTile', 'Card', 'InkWell'}.contains(c['type'])
                ? '${c['type']}'
                : '${c['type']}:${c['label']}';
            if (done.add(id)) {
              next = c;
              break;
            }
          }
          if (next == null) {
            // Nothing new here: back towards the start, or finished.
            if (here == pattern(start)) break;
            await _callExtensionRaw('ext.flutterpilot.pressBack', {});
            await _callExtensionRaw('ext.flutterpilot.waitForAnimation', {
              'timeoutMs': '1000',
            });
            final back = await route();
            if (back == current) {
              // No way back (a root tab): jump to the start.
              await _callExtensionRaw('ext.flutterpilot.navigateTo', {
                'route': start,
              });
              if (await route() == current) break;
            }
            continue;
          }
          taps++;
          final label = next['label'].toString();
          final tap = await _callExtensionRaw('ext.flutterpilot.tapWidget', {
            if (next['key'] != null)
              'key': next['key'].toString()
            else
              'text': label,
          });
          final to = tap.isError
              ? null
              : ((tap.data?['postActionState'] as Map?)?['route']?.toString() ??
                    await route());
          edges.add({
            'from': current,
            'to': to ?? '(tap failed: ${tap.errorMessage ?? 'refused'})',
            'via':
                '${next['type']} "${label.length > 40 ? '${label.substring(0, 40)}…' : label}"',
          });
        }

        var restored = current == start;
        if (p['restore'] != false && !restored) {
          await _callExtensionRaw('ext.flutterpilot.navigateTo', {
            'route': start,
          });
          await _callExtensionRaw('ext.flutterpilot.waitForAnimation', {
            'timeoutMs': '1000',
          });
          restored = await route() == start;
        }

        final buf = StringBuffer(
          'Crawled ${health.length} screen(s) with $taps tap(s)'
          '${taps >= maxTaps ? ' (stopped at maxScreens)' : ''}:',
        );
        for (final h in health.values) {
          final o = h['overflows'], a = h['a11y'];
          buf.write(
            '\n  ${h['route']}: '
            '${o == 0 && a == 0 ? 'clean' : '$o overflow(s), $a small tap target(s)'}',
          );
        }
        buf.write('\nGraph:');
        for (final edge in edges) {
          buf.write(
            '\n  ${edge['from']} → ${edge['to'] == edge['from'] ? '(same screen)' : edge['to']}  via ${edge['via']}',
          );
        }
        final sick = health.values
            .where((h) => h['overflows'] != 0 || h['a11y'] != 0)
            .map((h) => '"${h['route']}"');
        if (sick.isNotEmpty) {
          buf.write(
            '\nDetails: audit_screen_health(routes: [${sick.join(', ')}]).',
          );
        }
        if (!restored) buf.write('\nCould not get back to $start.');
        return CallToolResult(
          content: [TextContent(text: buf.toString())],
          structuredContent: {
            'screens': health.values.toList(),
            'edges': edges,
            'taps': taps,
            'restored': restored,
          },
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
      // Told to resize and the app saw nothing. Ask macOS which it was: a
      // window that refused (fixed, minimum or full-screen size), or one
      // that did resize while the app has not been told yet.
      final window = pid == null || context?.operatingSystem != 'macos'
          ? null
          : await readAppWindowSize(pid);
      final refused = window == null || !window.startsWith('${size.width}x');
      return (
        line: refused
            ? '✗ $label: the window was asked to resize but is still '
                  '${window ?? 'the same size'} (a fixed, minimum or '
                  'full-screen window); viewport $after.'
            : '✗ $label: the window is now $window but the app still '
                  'reports viewport $after: it has not received the new '
                  'size (a hidden or minimised window?). Try again.',
        failed: true,
      );
    }
    if (!after.startsWith('${size.width}x')) {
      // It moved, but not to the width asked for: a minimum or the screen.
      return (
        line:
            '– $label partly applied: the window stopped at a limit (its '
            'minimum size, or the screen); viewport now $after.',
        failed: false,
      );
    }
    return (line: '✓ $label (viewport now $after)', failed: false);
  }
}

/// The extension argument for `set_app_settings`'s `orientation`.
///
/// `auto` releases the pin and follows the sensor; every SDK version spells
/// that `all`, so the server translates instead of requiring a newer app.
String orientationExtensionArgument(String orientation) =>
    orientation == 'auto' ? 'all' : orientation;

/// What to tell the caller after a pinning `set_app_settings(orientation: …)`.
///
/// `SystemChrome.setPreferredOrientations` is applied to the running app and
/// stays in force: after it, physically rotating the phone does nothing until
/// `auto` is set or the app restarts. The tool used to say only
/// "✓ orientation landscape", which made that look like a device setting.
String? orientationPinNote(String orientation) => switch (orientation) {
  'portrait' || 'landscape' =>
    'note: the app stays pinned to $orientation — the phone no longer follows '
        'its sensor. Pass orientation:"auto" to release it (or restart the '
        'app).',
  _ => null,
};
