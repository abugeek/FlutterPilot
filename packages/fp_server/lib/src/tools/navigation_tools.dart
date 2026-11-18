part of '../../fp_server.dart';

/// Tools for navigating routes and changing theme, locale, text scale,
/// orientation and the framework's debug overlays.
mixin _NavigationToolsMixin on _FlutterPilotServerBase {
  void _registerNavigationTools() {
    _tool(
      'navigate_to',
      description: 'Navigates to route or deep link (go_router or Navigator).',
      inputSchema: ToolInputSchema(
        properties: {
          'route': JsonSchema.string(description: 'Route or deep link URL.'),
          'action': JsonSchema.string(
            enumValues: ['go', 'push', 'replace'],
            description: 'Default "go" (push/replace use go_router).',
          ),
          'deepLink': JsonSchema.boolean(description: 'Open as OS deep link.'),
          'waitFor': JsonSchema.string(description: 'Key/text to await.'),
          'failureKey': JsonSchema.string(description: 'Fast-fail key.'),
          'anyOf': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Keys to await.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Wait timeout ms (5000).',
          ),
          'pathParams': JsonSchema.object(description: 'Path params map.'),
          'queryParams': JsonSchema.object(description: 'Query params map.'),
        },
        required: ['route'],
      ),
      callback: (p, e) async {
        final rawRoute = p['route'].toString();
        final action = p['action']?.toString() ?? 'go';
        final pathParams = p['pathParams'] as Map<String, dynamic>?;
        final queryParams = p['queryParams'] as Map<String, dynamic>?;

        var route = rawRoute;
        if (pathParams != null && pathParams.isNotEmpty) {
          for (final entry in pathParams.entries) {
            final key = entry.key;
            final val = Uri.encodeComponent('${entry.value}');
            route = route.replaceAll(':$key', val).replaceAll('{$key}', val);
          }
        }
        if (queryParams != null && queryParams.isNotEmpty) {
          final uri = Uri.tryParse(route);
          if (uri != null) {
            final merged = Map<String, dynamic>.from(uri.queryParameters);
            for (final entry in queryParams.entries) {
              merged[entry.key] = '${entry.value}';
            }
            final newQuery = Uri(queryParameters: merged).query;
            final base = route.split('?').first;
            route = newQuery.isNotEmpty ? '$base?$newQuery' : base;
          }
        }

        final isDeepLink = p['deepLink'] == true || route.contains('://');
        final _ExtensionResult res;
        if (isDeepLink) {
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
          String? suggestion;
          try {
            final cfg = await _callExtensionRaw(
              'ext.flutterpilot.getGoRouterConfig',
              {},
            );
            if (!cfg.isError && cfg.data != null) {
              final known = _extractRoutePaths(cfg.data);
              if (known.isNotEmpty) {
                final match = _findClosestPath(rawRoute, known);
                suggestion = match != null
                    ? ' Did you mean "$match"? Known routes: ${known.take(5).join(', ')}.'
                    : ' Known routes: ${known.take(5).join(', ')}.';
              }
            }
          } catch (_) {}

          final errText =
              '${res.errorMessage ?? 'Navigation failed'}.${suggestion ?? ''}';
          return withVerdict(
            CallToolResult(
              isError: true,
              content: [TextContent(text: errText)],
            ),
            navigationVerdict(
              requested: rawRoute,
              resolvedUri: route,
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
        final failureKey = p['failureKey']?.toString();
        final rawAnyOf = p['anyOf'];
        final anyOfStr = rawAnyOf is List
            ? rawAnyOf.map((s) => s.toString()).join(',')
            : rawAnyOf?.toString();
        final timeoutMs = (p['timeoutMs'] as num?)?.toInt() ?? 5000;
        final timeoutSec = (timeoutMs / 1000).toStringAsFixed(
          timeoutMs % 1000 == 0 ? 0 : 1,
        );
        final waitRequired =
            (waitFor != null && waitFor.isNotEmpty) ||
            failureKey != null ||
            anyOfStr != null;
        final stackFuture = _callExtensionRaw(
          'ext.flutterpilot.getNavigationStack',
          {},
        );
        final screenFuture = !waitRequired ? _screenAfter(route: false) : null;
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
        if (waitRequired) {
          final found =
              await _callExtensionRaw('ext.flutterpilot.waitForCondition', {
                if (waitFor != null && waitFor.isNotEmpty) 'selector': waitFor,
                'anyOf': ?anyOfStr,
                'failureKey': ?failureKey,
                'timeoutMs': '$timeoutMs',
              });
          missing = found.isError;
          final targetDesc = waitFor ?? anyOfStr ?? 'target';
          waited = missing
              ? ' But "$targetDesc" did not appear within $timeoutSec s${found.errorMessage != null ? ': ${found.errorMessage}' : '.'}'
              : ' "$targetDesc" is on screen.';
        }
        final routeLabel = rawRoute != route
            ? '$route (from "$rawRoute")'
            : route;
        return CallToolResult(
          isError: missing,
          content: [
            TextContent(
              text:
                  'Navigated to "$routeLabel"${now != null ? '. Stack: $now' : ''}.'
                  '$waited${screenFuture == null ? await _screenAfter(route: false) : await screenFuture}',
            ),
          ],
          // The compact twin: what was asked for, where the app now says it
          // is, whether the wait succeeded, and whether the route is
          // confirmed (an unreadable stack leaves it uncertain).
          structuredContent: navigationVerdict(
            requested: rawRoute,
            resolvedUri: route,
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
          'Navigation stack and route locations. waitForRoute polls until matching '
          'route appears; routes/history add router table.',
      inputSchema: ToolInputSchema(
        properties: {
          'routes': JsonSchema.boolean(
            description: 'Include go_router\'s configured routes.',
          ),
          'history': JsonSchema.boolean(
            description: 'Include recent route changes (go_router).',
          ),
          'query': JsonSchema.string(
            description: 'Filter routes or history by substring.',
          ),
          'waitForRoute': JsonSchema.string(
            description: 'Poll until current route equals or contains this.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Timeout in ms for waitForRoute (default 3000).',
          ),
        },
      ),
      callback: (p, e) async {
        final waitForRoute = p['waitForRoute']?.toString();
        final timeoutMs =
            (p['timeoutMs'] as num?)?.toInt().clamp(100, 30000) ?? 3000;

        if (waitForRoute != null && waitForRoute.isNotEmpty) {
          final stopwatch = Stopwatch()..start();
          while (stopwatch.elapsedMilliseconds < timeoutMs) {
            final res = await _callExtensionRaw(
              'ext.flutterpilot.getNavigationStack',
              {},
            );
            final router = await _callExtensionRaw(
              'ext.flutterpilot.getGoRouterState',
              {},
            );
            final loc = router.data?['currentLocation']?.toString();
            final stack =
                (res.data?['stack'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const [];
            final current = loc ?? (stack.isNotEmpty ? stack.last : null);
            if (current != null &&
                (current == waitForRoute || current.contains(waitForRoute))) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }

        final stackFuture = _callExtensionRaw(
          'ext.flutterpilot.getNavigationStack',
          {},
        );
        final routerFuture = _callExtensionRaw(
          'ext.flutterpilot.getGoRouterState',
          {},
        );
        final extras =
            <({String flag, String label, Future<_ExtensionResult> future})>[
              if (p['routes'] == true)
                (
                  flag: 'routes',
                  label: 'Routes',
                  future: _callExtensionRaw(
                    'ext.flutterpilot.getGoRouterConfig',
                    {},
                  ),
                ),
              if (p['history'] == true)
                (
                  flag: 'history',
                  label: 'History',
                  future: _callExtensionRaw(
                    'ext.flutterpilot.getGoRouterHistory',
                    {},
                  ),
                ),
            ];
        final res = await stackFuture;
        if (res.isError) return res.toCallToolResult();
        final buf = StringBuffer(
          'Navigation stack: ${(res.data?['stack'] as List?)?.join(' -> ') ?? 'empty'}',
        );
        final router = await routerFuture;
        if (!router.isError) {
          final json = router.data!;
          buf.write('\ngo_router location: ${json['currentLocation']}');
          final pathParams = json['pathParameters'] as Map? ?? {};
          if (pathParams.isNotEmpty) buf.write('\nPath params: $pathParams');
          final queryParams = json['queryParameters'] as Map? ?? {};
          if (queryParams.isNotEmpty) buf.write('\nQuery params: $queryParams');
          buf.write('\nCan pop: ${json['canPop']}');
          final queryStr = p['query']?.toString().toLowerCase();
          for (final m in json['matchedRoutes'] as List? ?? const []) {
            final loc = '${m['matchedLocation']} → ${m['route']}';
            if (queryStr != null &&
                queryStr.isNotEmpty &&
                !loc.toLowerCase().contains(queryStr)) {
              continue;
            }
            buf.write('\n  Matched: $loc');
          }
          final extraResults = extras.isEmpty
              ? const <_ExtensionResult>[]
              : await Future.wait([for (final item in extras) item.future]);
          for (var i = 0; i < extras.length; i++) {
            final flag = extras[i].flag;
            final label = extras[i].label;
            final extra = extraResults[i];
            Object? dataToFormat = extra.data;
            if (queryStr != null && queryStr.isNotEmpty && extra.data != null) {
              if (flag == 'routes' && extra.data is Map) {
                final map = Map<String, dynamic>.from(extra.data as Map);
                final rList = map['routes'] as List?;
                if (rList != null) {
                  map['routes'] = rList
                      .where(
                        (r) => r.toString().toLowerCase().contains(queryStr),
                      )
                      .toList();
                  dataToFormat = map;
                }
              } else if (flag == 'history' && extra.data is List) {
                dataToFormat = (extra.data as List)
                    .where((h) => h.toString().toLowerCase().contains(queryStr))
                    .toList();
              }
            }
            buf.write(
              '\n$label: ${extra.isError ? extra.errorMessage : jsonEncode(dataToFormat)}',
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
          'Sets theme, locale, text scale, orientation, window size, or '
          'debug overlays.',
      inputSchema: ToolInputSchema(
        properties: {
          'reset': JsonSchema.boolean(
            description: 'Restore defaults and clear overlays.',
          ),
          'theme': JsonSchema.string(
            enumValues: ['light', 'dark'],
            description: 'App brightness.',
          ),
          'locale': JsonSchema.string(description: 'BCP-47 tag or "system".'),
          'textScale': JsonSchema.number(description: 'Text scale factor.'),
          'keyboardInset': JsonSchema.number(
            description: 'Keyboard height in dp (0 clears).',
          ),
          'orientation': JsonSchema.string(
            enumValues: ['portrait', 'landscape', 'all', 'auto'],
            description: 'Phones.',
          ),
          'windowSize': JsonSchema.string(description: 'WIDTHxHEIGHT.'),
          'debugPaint': JsonSchema.boolean(description: 'Show layout bounds.'),
          'repaintRainbow': JsonSchema.boolean(
            description: 'Show repaint rainbow.',
          ),
          'slowAnimations': JsonSchema.boolean(
            description: '5x slow animations.',
          ),
        },
      ),
      callback: (p, e) async {
        final isReset = p['reset'] == true;
        final steps = <(String, String, Map<String, dynamic>)>[
          if (p['theme'] != null || isReset)
            (
              'theme ${p['theme'] ?? 'light'}',
              'ext.flutter.brightnessOverride',
              {
                'value': p['theme'] == 'dark'
                    ? 'Brightness.dark'
                    : 'Brightness.light',
              },
            ),
          if (p['locale'] != null || isReset)
            (
              'locale ${p['locale'] ?? 'system'}',
              'ext.flutterpilot.setLocale',
              {'locale': (p['locale'] ?? 'system').toString()},
            ),
          if (p['textScale'] != null || isReset)
            (
              'text scale ${p['textScale'] ?? '0'}',
              'ext.flutterpilot.setTextScaleFactor',
              {'scale': (p['textScale'] ?? '0').toString()},
            ),
          if (p['keyboardInset'] != null || isReset)
            (
              'keyboard inset ${p['keyboardInset'] ?? '0'}',
              'ext.flutterpilot.setKeyboardInset',
              {'inset': (p['keyboardInset'] ?? '0').toString()},
            ),
          if (p['orientation'] != null || isReset)
            (
              'orientation ${p['orientation'] ?? 'all'}',
              'ext.flutterpilot.setOrientation',
              {
                'orientation': orientationExtensionArgument(
                  (p['orientation'] ?? 'all').toString(),
                ),
              },
            ),
          if (p['debugPaint'] != null || isReset)
            (
              'debug paint ${p['debugPaint'] == true ? 'on' : 'off'}',
              'ext.flutter.debugPaint',
              {'enabled': (p['debugPaint'] == true).toString()},
            ),
          if (p['repaintRainbow'] != null || isReset)
            (
              'repaint rainbow ${p['repaintRainbow'] == true ? 'on' : 'off'}',
              'ext.flutter.repaintRainbow',
              {'enabled': (p['repaintRainbow'] == true).toString()},
            ),
          if (p['slowAnimations'] != null || isReset)
            (
              'slow animations ${p['slowAnimations'] == true ? 'on' : 'off'}',
              'ext.flutter.timeDilation',
              {'timeDilation': p['slowAnimations'] == true ? '5.0' : '1.0'},
            ),
        ];
        if (steps.isEmpty && p['windowSize'] == null && !isReset) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'Nothing to change: pass theme, locale, textScale, '
                    'keyboardInset, orientation, windowSize, debugPaint, repaintRainbow, '
                    'slowAnimations or reset: true.',
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
      'crawl_app',
      description:
          'Crawls reachable screens via list rows and tabs; reports route graph '
          'and health issues, then restores start route.',
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
          'audit': JsonSchema.boolean(
            description:
                'Include detailed health findings for screens with issues.',
          ),
        },
      ),
      callback: (p, e) async {
        final maxTaps = (p['maxScreens'] as num?)?.toInt() ?? 15;
        final shouldAudit = p['audit'] == true;
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
        final screenAudit = <String, List<dynamic>>{};
        final edges = <Map<String, String>>[];
        // route pattern → what was tapped there (a list's rows count once)
        final tried = <String, Set<String>>{};
        var taps = 0;
        var current = start;

        while (taps < maxTaps) {
          final screenFuture = _callExtensionRaw(
            'ext.flutterpilot.crawlScreen',
            {},
          );
          final auditFuture = shouldAudit
              ? _callExtensionRaw('ext.flutterpilot.auditScreenHealth', {})
              : null;
          final screen = await screenFuture;
          if (screen.isError) return screen.toCallToolResult();
          final data = screen.data ?? const <String, dynamic>{};
          current = data['currentRoute']?.toString() ?? current;
          final here = pattern(current);
          health.putIfAbsent(
            here,
            () => {
              'route': current,
              'overflows': (data['overflowCount'] as num?)?.toInt() ?? 0,
              'a11y': (data['accessibilityIssueCount'] as num?)?.toInt() ?? 0,
            },
          );
          if (auditFuture != null) {
            final auditRes = await auditFuture;
            final findings = (auditRes.data?['findings'] as List?) ?? const [];
            if (findings.isNotEmpty) {
              screenAudit[current] = findings;
            }
          }
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

        var restored = (await route()) == start;
        if (p['restore'] != false && !restored) {
          for (var i = 0; i < taps && (await route()) != start; i++) {
            final popped = await _callExtensionRaw(
              'ext.flutterpilot.pressBack',
              {},
            );
            if (popped.isError || (popped.data?['popped'] == false)) break;
            await _callExtensionRaw('ext.flutterpilot.waitForAnimation', {
              'timeoutMs': '300',
            });
          }
          if ((await route()) != start) {
            await _callExtensionRaw('ext.flutterpilot.navigateTo', {
              'route': start,
            });
            await _callExtensionRaw('ext.flutterpilot.waitForAnimation', {
              'timeoutMs': '600',
            });
          }
          restored = (await route()) == start;
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
        if (screenAudit.isNotEmpty) {
          buf.write('\nAudit Details:');
          for (final entry in screenAudit.entries) {
            buf.write('\n  • ${entry.key}:');
            for (final f in entry.value) {
              if (f is Map) {
                final src = f['source'] != null ? ' at ${f['source']}' : '';
                buf.write('\n    - ${f['details'] ?? f['type']}$src');
              }
            }
          }
        } else if (sick.isNotEmpty) {
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
  @override
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

  List<String> _extractRoutePaths(Object? data, [String parent = '']) {
    final paths = <String>[];
    if (data is List) {
      for (final item in data) {
        paths.addAll(_extractRoutePaths(item, parent));
      }
    } else if (data is Map) {
      final rawPath = data['path']?.toString();
      var currentPath = parent;
      if (rawPath != null && rawPath.isNotEmpty) {
        if (rawPath.startsWith('/')) {
          currentPath = rawPath;
        } else {
          currentPath = parent.endsWith('/')
              ? '$parent$rawPath'
              : '$parent/$rawPath';
        }
        paths.add(currentPath);
      }
      final children = data['children'] ?? data['routes'];
      if (children != null) {
        paths.addAll(_extractRoutePaths(children, currentPath));
      }
    }
    return paths;
  }

  String? _findClosestPath(String target, List<String> paths) {
    if (paths.isEmpty) return null;
    final cleanTarget = target.split('?').first.toLowerCase();
    String? best;
    int bestMatchLength = 0;
    for (final p in paths) {
      final cleanP = p.toLowerCase();
      if (cleanP == cleanTarget) return p;
      if (cleanP == '/') continue;
      if (cleanP.startsWith(cleanTarget) || cleanTarget.startsWith(cleanP)) {
        if (cleanP.length > bestMatchLength) {
          best = p;
          bestMatchLength = cleanP.length;
        }
      }
    }
    return best ?? paths.firstWhere((p) => p != '/', orElse: () => paths.first);
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
